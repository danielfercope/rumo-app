from typing import NamedTuple

import httpx

from ..config import settings
from ..errors import GeocodingNotFoundError, UpstreamIntegrationError

BASE_URL = "https://maps.googleapis.com/maps/api/geocode/json"


class Geocode(NamedTuple):
    latitude: float
    longitude: float
    # location_type do Google (ROOFTOP, RANGE_INTERPOLATED, ...); vai pra
    # companies.precisao_geocodificacao, igual ao cadastro feito pelo app.
    precisao: str


class GeocodingService:
    """Geocodificação de endereço no Backend. Hoje usa a Google Geocoding API
    (a mesma que o app usa no cadastro manual, só que com chave de servidor).
    Nome agnóstico de propósito, como CrmService/CompanyLookupService."""

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(timeout=10.0)

    async def aclose(self) -> None:
        await self._client.aclose()

    async def geocode(self, address: str) -> Geocode:
        try:
            response = await self._client.get(
                BASE_URL,
                params={
                    "address": address,
                    "key": settings.geocoding_api_key,
                    "region": "br",
                    "components": "country:BR",
                },
            )
        except httpx.RequestError as exc:
            # str(exc) não inclui a URL (e portanto a chave).
            raise UpstreamIntegrationError(
                f"Falha de rede ao geocodificar: {exc}"
            ) from exc

        if response.status_code >= 400:
            raise UpstreamIntegrationError(
                f"Geocoding respondeu {response.status_code}"
            )

        data = response.json()
        status = data.get("status")
        if status == "ZERO_RESULTS":
            raise GeocodingNotFoundError(f"Endereço sem coordenadas: {address}")
        if status != "OK":
            raise UpstreamIntegrationError(
                f"Geocoding falhou ({status}): {data.get('error_message', '')}"
            )

        geometry = data["results"][0]["geometry"]
        location = geometry["location"]
        return Geocode(
            latitude=float(location["lat"]),
            longitude=float(location["lng"]),
            precisao=geometry.get("location_type") or "APPROXIMATE",
        )
