import httpx
import jwt
import pytest
import respx

from app.config import settings
from app.errors import UpstreamIntegrationError
from app.services.postgrest_client import PostgrestClient

BASE = "http://postgrest:3000"


@pytest.fixture
def db():
    return PostgrestClient(client=httpx.AsyncClient(base_url=BASE))


@respx.mock
async def test_select_envia_token_interno_com_role_crm_sync(db):
    route = respx.get(f"{BASE}/companies").mock(
        return_value=httpx.Response(200, json=[{"id": "1"}])
    )

    rows = await db.select("companies", {"cnpj": "eq.1"})

    assert rows == [{"id": "1"}]
    request = route.calls.last.request
    token = request.headers["Authorization"].removeprefix("Bearer ")
    claims = jwt.decode(token, settings.internal_jwt_secret, algorithms=["HS256"])
    assert claims["role"] == "crm_sync"


@respx.mock
async def test_insert_ignorando_duplicados(db):
    route = respx.post(f"{BASE}/companies").mock(return_value=httpx.Response(201))

    await db.insert("companies", [{"cnpj": "1"}], on_conflict="cnpj",
                    ignore_duplicates=True)

    request = route.calls.last.request
    assert request.url.params["on_conflict"] == "cnpj"
    assert "resolution=ignore-duplicates" in request.headers["Prefer"]


@respx.mock
async def test_upsert_faz_merge(db):
    route = respx.post(f"{BASE}/crm_sync_state").mock(return_value=httpx.Response(201))

    await db.upsert("crm_sync_state", [{"key": "companies"}], on_conflict="key")

    assert "resolution=merge-duplicates" in route.calls.last.request.headers["Prefer"]


@respx.mock
async def test_erro_http_vira_falha_de_integracao(db):
    respx.get(f"{BASE}/companies").mock(return_value=httpx.Response(500, text="boom"))

    with pytest.raises(UpstreamIntegrationError, match="500"):
        await db.select("companies", {})


@respx.mock
async def test_reaproveita_o_token_entre_chamadas(db):
    route = respx.get(f"{BASE}/companies").mock(return_value=httpx.Response(200, json=[]))

    await db.select("companies", {})
    await db.select("companies", {})

    tokens = {c.request.headers["Authorization"] for c in route.calls}
    assert len(tokens) == 1
