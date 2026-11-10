import httpx
import pytest
import respx

from app.errors import GeocodingNotFoundError, UpstreamIntegrationError
from app.services.geocoding_service import BASE_URL, GeocodingService


@pytest.fixture
def service():
    return GeocodingService(client=httpx.AsyncClient())


@respx.mock
async def test_geocode_devolve_coordenadas_e_precisao(service):
    route = respx.get(BASE_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "status": "OK",
                "results": [
                    {
                        "geometry": {
                            "location": {"lat": -26.3, "lng": -48.8},
                            "location_type": "ROOFTOP",
                        }
                    }
                ],
            },
        )
    )

    geo = await service.geocode("Rua A, 10 - Centro, Joinville - SC")

    assert (geo.latitude, geo.longitude, geo.precisao) == (-26.3, -48.8, "ROOFTOP")
    assert route.calls.last.request.url.params["address"].startswith("Rua A")
    assert route.calls.last.request.url.params["components"] == "country:BR"


@respx.mock
async def test_geocode_zero_results(service):
    respx.get(BASE_URL).mock(
        return_value=httpx.Response(200, json={"status": "ZERO_RESULTS", "results": []})
    )

    with pytest.raises(GeocodingNotFoundError):
        await service.geocode("endereço inexistente")


@respx.mock
async def test_geocode_status_de_erro_vira_falha_de_integracao(service):
    respx.get(BASE_URL).mock(
        return_value=httpx.Response(
            200, json={"status": "REQUEST_DENIED", "error_message": "chave inválida"}
        )
    )

    with pytest.raises(UpstreamIntegrationError, match="REQUEST_DENIED"):
        await service.geocode("Rua A")


@respx.mock
async def test_geocode_erro_de_rede(service):
    respx.get(BASE_URL).mock(side_effect=httpx.ConnectError("sem rede"))

    with pytest.raises(UpstreamIntegrationError):
        await service.geocode("Rua A")
