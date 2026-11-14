"""Google Places (API New): como a empresa aparece no Google — foto de capa,
nota, avaliações, telefone, site, horários e link do Maps.

Termos do Google Maps: só o identificador do lugar (`place_id`) pode ser
guardado; o conteúdo (nota, telefone, horários, foto) é buscado na hora. Por
isso há dois caminhos:
  - `search`: busca por texto (nome + cidade, puxada pra perto da coordenada da
    empresa) — só na primeira vez, pra descobrir o `place_id`;
  - `details`: pelo `place_id` guardado — as vezes seguintes.
O resultado da busca pode ser outro estabelecimento com nome parecido: o app
mostra o nome encontrado pra pessoa conferir. Cada chamada é cobrada."""

import httpx

from .base import SourceNotFound, SourceUnavailable, blank_to_none

SEARCH_URL = "https://places.googleapis.com/v1/places:searchText"
DETAILS_URL = "https://places.googleapis.com/v1/places/{place_id}"
PHOTO_URL = "https://places.googleapis.com/v1/{photo}/media"

_FIELDS = (
    "id",
    "displayName",
    "formattedAddress",
    "rating",
    "userRatingCount",
    "nationalPhoneNumber",
    "websiteUri",
    "googleMapsUri",
    "businessStatus",
    "regularOpeningHours.periods",
    "regularOpeningHours.weekdayDescriptions",
    "primaryTypeDisplayName",
    "photos",
)
SEARCH_FIELDS = ",".join(f"places.{f}" for f in _FIELDS)
DETAILS_FIELDS = ",".join(_FIELDS)

PHOTO_MAX_WIDTH = 800

_STATUS = {
    "OPERATIONAL": "Em funcionamento",
    "CLOSED_TEMPORARILY": "Fechado temporariamente",
    "CLOSED_PERMANENTLY": "Fechado permanentemente",
}


def _headers(api_key: str, fields: str | None = None) -> dict:
    h = {"X-Goog-Api-Key": api_key}  # no cabeçalho, nunca na URL (logs)
    if fields:
        h["X-Goog-FieldMask"] = fields
    return h


async def _call(client: httpx.AsyncClient, method: str, url: str, **kwargs):
    try:
        response = await client.request(method, url, **kwargs)
    except httpx.HTTPError as exc:
        raise SourceUnavailable(f"Falha de rede no Google Places: {exc}") from exc
    return response


async def search(
    client: httpx.AsyncClient,
    api_key: str,
    nome: str,
    cidade: str | None,
    uf: str | None,
    lat: float | None = None,
    lon: float | None = None,
) -> dict:
    query = " ".join(p for p in (nome, cidade, uf) if p)
    body: dict = {"textQuery": query, "languageCode": "pt-BR", "maxResultCount": 1}
    if lat is not None and lon is not None:
        body["locationBias"] = {
            "circle": {"center": {"latitude": lat, "longitude": lon}, "radius": 1000.0}
        }
    response = await _call(
        client, "POST", SEARCH_URL, json=body, headers=_headers(api_key, SEARCH_FIELDS)
    )
    if response.status_code >= 400:
        # 403 = API não ativada na chave / sem cobrança; não vale expor o corpo
        raise SourceUnavailable(f"Google Places respondeu {response.status_code}")
    places = (response.json() or {}).get("places") or []
    if not places:
        raise SourceNotFound(query)
    return normalize(places[0])


async def details(client: httpx.AsyncClient, api_key: str, place_id: str) -> dict:
    """Lugar pelo `place_id` guardado. Id que deixou de existir (o Google às vezes
    os troca) → SourceNotFound, pra quem chamou buscar de novo por nome."""
    response = await _call(
        client,
        "GET",
        DETAILS_URL.format(place_id=place_id),
        params={"languageCode": "pt-BR"},
        headers=_headers(api_key, DETAILS_FIELDS),
    )
    if response.status_code in (400, 404):
        raise SourceNotFound(place_id)
    if response.status_code >= 400:
        raise SourceUnavailable(f"Google Places respondeu {response.status_code}")
    return normalize(response.json() or {})


async def photo_url(
    client: httpx.AsyncClient, api_key: str, photo: str, max_width: int = PHOTO_MAX_WIDTH
) -> str:
    """Link temporário (googleusercontent, sem a chave) pra o app baixar a foto."""
    response = await _call(
        client,
        "GET",
        PHOTO_URL.format(photo=photo),
        params={"maxWidthPx": max_width, "skipHttpRedirect": "true"},
        headers=_headers(api_key),
    )
    if response.status_code >= 400:
        raise SourceUnavailable(f"Foto do Google respondeu {response.status_code}")
    uri = (response.json() or {}).get("photoUri")
    if not uri:
        raise SourceUnavailable("Foto do Google sem link")
    return uri


def normalize(p: dict) -> dict:
    hours = p.get("regularOpeningHours") or {}
    photos = p.get("photos") or []
    cover = photos[0] if photos else None
    author = ((cover or {}).get("authorAttributions") or [{}])[0] if cover else {}
    return {
        "place_id": p.get("id"),
        "nome": blank_to_none((p.get("displayName") or {}).get("text")),
        "tipo": blank_to_none((p.get("primaryTypeDisplayName") or {}).get("text")),
        "endereco": blank_to_none(p.get("formattedAddress")),
        "nota": p.get("rating"),
        "avaliacoes": p.get("userRatingCount"),
        "telefone": blank_to_none(p.get("nationalPhoneNumber")),
        "site": blank_to_none(p.get("websiteUri")),
        "maps_url": blank_to_none(p.get("googleMapsUri")),
        "situacao": _STATUS.get(p.get("businessStatus")),
        "horarios": hours.get("weekdayDescriptions") or [],
        "periodos": [
            {
                "abre": _point(per.get("open")),
                "fecha": _point(per.get("close")),
            }
            for per in hours.get("periods") or []
            if per.get("open")
        ],
        # referência interna da capa; o serviço troca pelo link e pelo crédito
        "_foto": {
            "ref": cover.get("name"),
            "autor": blank_to_none(author.get("displayName")),
            "autor_url": blank_to_none(author.get("uri")),
        }
        if cover and cover.get("name")
        else None,
    }


def _point(p: dict | None) -> dict | None:
    if not p:
        return None
    return {"dia": p.get("day"), "hora": p.get("hour", 0), "minuto": p.get("minute", 0)}


def is_open(periodos: list[dict], now) -> bool | None:
    """Aberto em `now` (datetime no fuso local da empresa)? Nulo se não há
    horário. Dia do Google: 0 = domingo. Período sem `fecha` = 24 h."""
    if not periodos:
        return None
    google_day = (now.weekday() + 1) % 7  # Python: 0 = segunda
    minute_of_week = google_day * 1440 + now.hour * 60 + now.minute
    week = 7 * 1440
    for per in periodos:
        abre, fecha = per.get("abre"), per.get("fecha")
        if not abre:
            continue
        if not fecha:
            return True
        start = abre["dia"] * 1440 + abre["hora"] * 60 + abre["minuto"]
        end = fecha["dia"] * 1440 + fecha["hora"] * 60 + fecha["minuto"]
        if end <= start:
            end += week  # atravessa o fim da semana (sábado → domingo)
        for m in (minute_of_week, minute_of_week + week):
            if start <= m < end:
                return True
    return False
