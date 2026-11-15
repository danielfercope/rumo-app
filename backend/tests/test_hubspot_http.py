import httpx
import pytest
import respx

from app.services import hubspot_http
from app.services.crm_connector import CrmMapping, HubSpotConnector
from app.services.hubspot_http import HubSpotHttp

BASE = "https://api.hubapi.com"
SEARCH = f"{BASE}/crm/v3/objects/companies/search"


class FakeTime:
    """Relógio e sleep falsos: o sleep só avança o relógio."""

    def __init__(self):
        self.now = 100.0
        self.sleeps = []

    def clock(self):
        return self.now

    async def sleep(self, seconds):
        self.sleeps.append(round(seconds, 3))
        self.now += seconds


def _http(t):
    client = httpx.AsyncClient(base_url=BASE)
    return HubSpotHttp(client, sleep=t.sleep, clock=t.clock)


@respx.mock
async def test_busca_espacada_no_maximo_4_por_segundo():
    respx.post(SEARCH).respond(200, json={})
    t = FakeTime()
    http = _http(t)
    for _ in range(5):
        await http.send("POST", "/crm/v3/objects/companies/search", json={})
    # a 1ª sai na hora; as seguintes esperam 0,25 s cada
    assert t.sleeps == [0.25, 0.25, 0.25, 0.25]


@respx.mock
async def test_rotas_que_nao_sao_busca_nao_esperam():
    respx.get(f"{BASE}/crm/v3/objects/companies").respond(200, json={})
    t = FakeTime()
    http = _http(t)
    for _ in range(3):
        await http.send("GET", "/crm/v3/objects/companies")
    assert t.sleeps == []


@respx.mock
async def test_429_espera_e_tenta_de_novo():
    route = respx.post(SEARCH).mock(side_effect=[
        httpx.Response(429, json={"errorType": "RATE_LIMIT"}),
        httpx.Response(429, headers={"Retry-After": "3"}),
        httpx.Response(200, json={"results": []}),
    ])
    t = FakeTime()
    response = await _http(t).send("POST", "/crm/v3/objects/companies/search", json={})
    assert response.status_code == 200
    assert route.call_count == 3
    # recuo de 1 s (sem Retry-After) e depois os 3 s pedidos pelo HubSpot
    assert 1.0 in t.sleeps and 3.0 in t.sleeps


@respx.mock
async def test_429_persistente_desiste_e_devolve_o_429():
    route = respx.get(f"{BASE}/crm/v3/objects/companies").respond(429)
    t = FakeTime()
    response = await _http(t).send("GET", "/crm/v3/objects/companies")
    assert response.status_code == 429
    assert route.call_count == hubspot_http.MAX_RETRIES + 1
    assert max(t.sleeps) <= hubspot_http.MAX_BACKOFF_S


@respx.mock
async def test_conector_atravessa_o_limite_na_paginacao(monkeypatch):
    """O caso de produção: a prévia pagina a busca e o HubSpot devolve 429 no
    meio — antes virava erro 502; agora espera e continua."""
    t = FakeTime()
    monkeypatch.setattr(hubspot_http.asyncio, "sleep", t.sleep)
    monkeypatch.setattr(hubspot_http.time, "monotonic", t.clock)

    def page(after, ids):
        body = {"results": [
            {"id": i, "properties": {"cnpj": "11222333000181",
                                     "hs_lastmodifieddate": "2026-01-01T00:00:00Z"}}
            for i in ids]}
        if after:
            body["paging"] = {"next": {"after": after}}
        return httpx.Response(200, json=body)

    respx.post(SEARCH).mock(side_effect=[
        page("2", ["1"]),
        httpx.Response(429, json={"errorType": "RATE_LIMIT"}),
        page(None, ["2"]),
    ])
    connector = HubSpotConnector("tok")
    mapping = CrmMapping.from_json({"campo_cnpj": "cnpj"})
    ids = []
    async for records in connector.fetch_changes(None, mapping):
        ids += [r.external_id for r in records]
    await connector.aclose()
    assert ids == ["1", "2"]
