"""Orquestra o enriquecimento: quem pode ver, cache e falha isolada por fonte.

Cada fonte é pedida separadamente pelo app (`GET /enriquecimento/{fonte}`), pra
os blocos dos detalhes carregarem cada um no seu tempo: uma fonte lenta ou fora
do ar não segura as outras. A resposta sempre tem o mesmo envelope:

    {"fonte", "status": ok | vazio | indisponivel | desativado,
     "origem", "atualizado_em", "desatualizado", "dados", "mensagem"}

Cache em `enriquecimento_cache` (018): dentro da validade, não chama a fonte;
vencido e a fonte fora do ar, devolve o último dado marcado como desatualizado."""

import logging
from collections.abc import Awaitable, Callable
from datetime import datetime, timedelta, timezone

import httpx

from ..postgrest_client import PostgrestClient
from ..access_service import AccessService
from . import compras, google_places, receita, regional
from .base import SourceNotFound, SourceUnavailable, digits

logger = logging.getLogger("uvicorn.error.enrichment")

FONTES = ("receita", "compras", "comex", "municipio", "google")

ORIGEM = {
    "receita": "Receita Federal (via BrasilAPI / Minha Receita)",
    "compras": "Compras.gov.br e PNCP",
    "comex": "Comex Stat (MDIC)",
    "municipio": "IBGE",
    "google": "Google Maps",
}

TTL = {
    "receita": timedelta(days=7),
    "compras": timedelta(days=1),
    "comex": timedelta(days=30),
    "municipio": timedelta(days=30),
}

# Google: só o place_id fica guardado (termos do Google Maps); o Google
# recomenda renová-lo a cada 12 meses. "Não encontrado" é dado nosso e fica
# 7 dias, pra não repetir busca paga sem resultado.
PLACE_ID_KEY = "google_place_id"
PLACE_ID_TTL = timedelta(days=365)
NOT_FOUND_TTL = timedelta(days=7)

# Horário de Brasília (sem horário de verão desde 2019). Estados em UTC-4/-5
# ficam com "aberto agora" adiantado em 1–2 h.
BRT = timezone(timedelta(hours=-3))

CACHE = "enriquecimento_cache"


class EnrichmentService:
    def __init__(
        self,
        db: PostgrestClient,
        access: AccessService,
        *,
        client: httpx.AsyncClient | None = None,
        google_api_key: str = "",
        google_enabled: bool = True,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._db = db
        self._access = access
        self._client = client or httpx.AsyncClient(
            timeout=httpx.Timeout(15.0, connect=5.0),
            headers={"User-Agent": "rumo-app/1.0 (enriquecimento de dados publicos)"},
            follow_redirects=True,
        )
        self._owns_client = client is None
        self._google_key = google_api_key
        self._google_enabled = google_enabled
        self._ttl = dict(TTL)
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    async def aclose(self) -> None:
        if self._owns_client:
            await self._client.aclose()

    async def get(self, uid: str, group_id: str, cnpj: str, fonte: str) -> dict:
        if fonte not in FONTES:
            raise ValueError(f"Fonte desconhecida: {fonte}")
        await self._access.require_member(uid, group_id)
        await self._access.require_cnpj_in_portfolio(group_id, cnpj)
        cnpj = digits(cnpj)

        if fonte == "receita":
            return await self._receita(cnpj)
        if fonte == "compras":
            return await self._cached(
                "compras", cnpj, lambda: compras.fetch(self._client, cnpj)
            )
        if fonte in ("comex", "municipio"):
            return await self._regional(fonte, cnpj)
        return await self._google(cnpj)

    # ─── Fontes ─────────────────────────────────────────────────────────

    async def _receita(self, cnpj: str) -> dict:
        return await self._cached(
            "receita", cnpj, lambda: receita.fetch(self._client, cnpj)
        )

    async def _regional(self, fonte: str, cnpj: str) -> dict:
        cad = await self._receita(cnpj)
        dados = cad.get("dados") or {}
        ibge = dados.get("codigo_municipio_ibge")
        if not ibge:
            return self._envelope(
                fonte,
                "indisponivel" if cad["status"] == "indisponivel" else "vazio",
                mensagem="Município da empresa não identificado.",
            )
        fetcher = (
            (lambda: regional.comex(self._client, ibge))
            if fonte == "comex"
            else (lambda: regional.municipio(self._client, ibge))
        )
        env = await self._cached(fonte, str(ibge), fetcher)
        if env.get("dados") is not None:
            env["dados"]["municipio"] = await self._city_name(
                str(ibge), env["dados"], dados.get("endereco") or {}
            )
        return env

    async def _city_name(self, ibge: str, dados: dict, end: dict) -> str | None:
        """Nome oficial do IBGE (com acento); pro comex, aproveita o do cache
        do IBGE; sem nenhum, monta a partir do endereço da Receita."""
        if dados.get("nome_ibge"):
            return dados["nome_ibge"]
        cached = await self._read_cache("municipio", ibge)
        nome = ((cached or {}).get("dados") or {}).get("nome_ibge")
        return nome or _municipio_label(end)

    async def _google(self, cnpj: str) -> dict:
        if not self._google_enabled or not self._google_key:
            return self._envelope(
                "google",
                "desativado",
                mensagem="Busca no Google desligada no servidor.",
            )
        cad = await self._receita(cnpj)
        dados = cad.get("dados") or {}
        end = dados.get("endereco") or {}
        rows = await self._db.select(
            "companies",
            {
                "cnpj": f"eq.{cnpj}",
                "select": "razao_social,nome_fantasia,municipio,uf,latitude,longitude",
                "limit": "1",
            },
        )
        row = rows[0] if rows else {}
        nome = (
            dados.get("nome_fantasia")
            or row.get("nome_fantasia")
            or dados.get("razao_social")
            or row.get("razao_social")
        )
        if not nome:
            return self._envelope("google", "vazio", mensagem="Empresa sem nome.")

        return await self._google_place(
            cnpj,
            lambda: google_places.search(
                self._client,
                self._google_key,
                nome,
                end.get("municipio") or row.get("municipio"),
                end.get("uf") or row.get("uf"),
                _float(row.get("latitude")),
                _float(row.get("longitude")),
            ),
        )

    async def _google_place(
        self, cnpj: str, search: Callable[[], Awaitable[dict]]
    ) -> dict:
        """Conteúdo do Google sempre na hora; só o place_id vem do cache."""
        now = self._clock()
        cached = await self._read_cache(PLACE_ID_KEY, cnpj)
        stored = (cached or {}).get("dados") or {}
        age = now - cached["buscado_em"] if cached else None
        if stored.get("_vazio") and age is not None and age < NOT_FOUND_TTL:
            return self._envelope("google", "vazio", atualizado_em=cached["buscado_em"])

        try:
            place = None
            place_id = stored.get("place_id")
            if place_id and age is not None and age < PLACE_ID_TTL:
                try:
                    place = await google_places.details(
                        self._client, self._google_key, place_id
                    )
                except SourceNotFound:
                    place = None  # id trocado pelo Google: busca de novo
            if place is None:
                try:
                    place = await search()
                except SourceNotFound:
                    await self._write_cache(PLACE_ID_KEY, cnpj, {"_vazio": True}, now)
                    return self._envelope("google", "vazio", atualizado_em=now)
                if place.get("place_id"):
                    await self._write_cache(
                        PLACE_ID_KEY, cnpj, {"place_id": place["place_id"]}, now
                    )
        except (SourceUnavailable, httpx.HTTPError) as exc:
            logger.warning("Google indisponível para %s: %s", cnpj, exc)
            return self._envelope(
                "google",
                "indisponivel",
                mensagem="O Google não respondeu agora. Tente de novo mais tarde.",
            )

        ref = place.pop("_foto", None)
        place["foto"] = None
        if ref and ref.get("ref"):
            try:
                url = await google_places.photo_url(
                    self._client, self._google_key, ref["ref"]
                )
                place["foto"] = {
                    "url": url,
                    "autor": ref.get("autor"),
                    "autor_url": ref.get("autor_url"),
                }
            except (SourceUnavailable, httpx.HTTPError) as exc:
                logger.info("Sem foto do Google para %s: %s", cnpj, exc)
        place["aberto_agora"] = google_places.is_open(
            place.get("periodos") or [], now.astimezone(BRT)
        )
        return self._envelope("google", "ok", dados=place, atualizado_em=now)

    # ─── Cache ──────────────────────────────────────────────────────────

    async def _cached(
        self, fonte: str, chave: str, fetcher: Callable[[], Awaitable[dict]]
    ) -> dict:
        now = self._clock()
        cached = await self._read_cache(fonte, chave)
        if cached and now - cached["buscado_em"] < self._ttl[fonte]:
            return self._from_cache(fonte, cached, stale=False)

        try:
            dados = await fetcher()
        except SourceNotFound:
            await self._write_cache(fonte, chave, {"_vazio": True}, now)
            return self._envelope(fonte, "vazio", atualizado_em=now)
        except (SourceUnavailable, httpx.HTTPError) as exc:
            logger.warning("Fonte %s indisponível para %s: %s", fonte, chave, exc)
            if cached:
                return self._from_cache(fonte, cached, stale=True)
            return self._envelope(
                fonte,
                "indisponivel",
                mensagem="A fonte não respondeu agora. Tente de novo mais tarde.",
            )
        except Exception:  # bug numa fonte não pode derrubar os detalhes
            logger.exception("Falha inesperada na fonte %s para %s", fonte, chave)
            if cached:
                return self._from_cache(fonte, cached, stale=True)
            return self._envelope(fonte, "indisponivel", mensagem="Erro ao consultar a fonte.")

        await self._write_cache(fonte, chave, dados, now)
        return self._envelope(fonte, "ok", dados=dados, atualizado_em=now)

    async def _read_cache(self, fonte: str, chave: str) -> dict | None:
        try:
            rows = await self._db.select(
                CACHE,
                {
                    "fonte": f"eq.{fonte}",
                    "chave": f"eq.{chave}",
                    "select": "dados,buscado_em",
                    "limit": "1",
                },
            )
        except Exception:
            logger.warning("Cache de enriquecimento indisponível", exc_info=True)
            return None
        if not rows:
            return None
        row = rows[0]
        return {
            "dados": row["dados"],
            "buscado_em": datetime.fromisoformat(row["buscado_em"]),
        }

    async def _write_cache(self, fonte: str, chave: str, dados: dict, now: datetime) -> None:
        try:
            await self._db.upsert(
                CACHE,
                [{"fonte": fonte, "chave": chave, "dados": dados, "buscado_em": now.isoformat()}],
                on_conflict="fonte,chave",
            )
        except Exception:
            logger.warning("Não foi possível gravar o cache de %s", fonte, exc_info=True)

    def _from_cache(self, fonte: str, cached: dict, *, stale: bool) -> dict:
        dados = cached["dados"]
        if isinstance(dados, dict) and dados.get("_vazio"):
            return self._envelope(fonte, "vazio", atualizado_em=cached["buscado_em"])
        return self._envelope(
            fonte,
            "ok",
            dados=dict(dados),
            atualizado_em=cached["buscado_em"],
            desatualizado=stale,
        )

    @staticmethod
    def _envelope(
        fonte: str,
        status: str,
        *,
        dados: dict | None = None,
        atualizado_em: datetime | None = None,
        desatualizado: bool = False,
        mensagem: str | None = None,
    ) -> dict:
        return {
            "fonte": fonte,
            "status": status,
            "origem": ORIGEM[fonte],
            "atualizado_em": atualizado_em.isoformat() if atualizado_em else None,
            "desatualizado": desatualizado,
            "dados": dados,
            "mensagem": mensagem,
        }


_LOWER = {"de", "da", "do", "das", "dos", "e"}


def _municipio_label(end: dict) -> str | None:
    cidade, uf = end.get("municipio"), end.get("uf")
    if not cidade:
        return None
    words = cidade.lower().split()
    name = " ".join(
        w if i and w in _LOWER else w[:1].upper() + w[1:] for i, w in enumerate(words)
    )
    return f"{name} ({uf})" if uf else name


def _float(value) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None
