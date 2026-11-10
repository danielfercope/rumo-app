import asyncio

import pytest
from fastapi.testclient import TestClient

from app import main
from app.internal_token import mint_internal_token
from app.errors import (
    CnpjNotFoundError,
    CrmCompanyNotFoundError,
    UnauthenticatedError,
    UpstreamIntegrationError,
)


@pytest.fixture
def client():
    # Sem `with`: não dispara o lifespan (testado à parte, abaixo).
    return TestClient(main.app)


@pytest.fixture
def auth():
    token = mint_internal_token("uid-1")["token"]
    return {"Authorization": f"Bearer {token}"}


def test_health(client):
    assert client.get("/health").json() == {"status": "ok"}


def test_auth_exchange_ok(client, monkeypatch):
    monkeypatch.setattr(
        main.auth_service,
        "exchange_token",
        lambda header: {"token": "t", "expires_at": 1, "header": header},
    )

    response = client.post("/auth/exchange", headers={"Authorization": "Bearer x"})

    assert response.status_code == 200
    assert response.json()["header"] == "Bearer x"


def test_auth_exchange_nao_autenticado(client, monkeypatch):
    def reject(header):
        raise UnauthenticatedError("token ruim")

    monkeypatch.setattr(main.auth_service, "exchange_token", reject)

    response = client.post("/auth/exchange", headers={"Authorization": "Bearer x"})

    assert response.status_code == 401
    assert response.json()["detail"] == "token ruim"


def test_auth_exchange_exige_o_header(client):
    assert client.post("/auth/exchange").status_code == 422


@pytest.mark.parametrize(
    "error, status",
    [(None, 200), (CnpjNotFoundError("sem cnpj"), 404),
     (UpstreamIntegrationError("brasilapi fora"), 502)],
)
def test_company_lookup(client, auth, monkeypatch, error, status):
    async def fake(cnpj):
        if error:
            raise error
        return {"cnpj": cnpj}

    monkeypatch.setattr(main.company_lookup_service, "lookup_cnpj", fake)

    response = client.post("/company-lookup", json={"cnpj": "123"}, headers=auth)

    assert response.status_code == status
    if status == 200:
        assert response.json() == {"cnpj": "123"}


@pytest.mark.parametrize(
    "error, status",
    [(None, 200), (CrmCompanyNotFoundError("sem empresa"), 404),
     (UpstreamIntegrationError("crm fora"), 502)],
)
def test_crm(client, auth, monkeypatch, error, status):
    async def fake(payload):
        if error:
            raise error
        return {"notes": []}

    monkeypatch.setattr(main.crm_service, "handle", fake)

    response = client.post(
        "/crm", json={"action": "getNotesWithOwners", "cnpj": "123"}, headers=auth
    )

    assert response.status_code == status
    if status == 200:
        assert response.json() == {"notes": []}


def test_crm_rejeita_acao_desconhecida(client, auth):
    response = client.post(
        "/crm", json={"action": "apagarTudo", "cnpj": "1"}, headers=auth
    )

    assert response.status_code == 422


@pytest.mark.parametrize(
    "path, body",
    [
        ("/company-lookup", {"cnpj": "123"}),
        ("/crm", {"action": "getNotesWithOwners", "cnpj": "123"}),
    ],
)
def test_endpoints_de_dados_exigem_autenticacao(client, monkeypatch, path, body):
    called = []

    async def fake(payload):
        called.append(payload)
        return {}

    monkeypatch.setattr(main.company_lookup_service, "lookup_cnpj", fake)
    monkeypatch.setattr(main.crm_service, "handle", fake)

    sem_header = client.post(path, json=body)
    token_ruim = client.post(
        path, json=body, headers={"Authorization": "Bearer lixo"}
    )
    token_do_job = client.post(
        path,
        json=body,
        headers={
            "Authorization": "Bearer "
            + mint_internal_token("crm-sync", role="crm_sync")["token"]
        },
    )

    assert sem_header.status_code == 422  # header obrigatório ausente
    assert token_ruim.status_code == 401
    assert token_do_job.status_code == 401
    assert called == []  # nenhuma consulta chegou ao CRM/BrasilAPI


@pytest.fixture
def fake_sync_loop(monkeypatch):
    state = {"started": 0, "cancelled": False}

    async def run_forever():
        state["started"] += 1
        try:
            await asyncio.sleep(3600)
        except asyncio.CancelledError:
            state["cancelled"] = True
            raise

    monkeypatch.setattr(main.crm_sync_service, "run_forever", run_forever)
    return state


def _boot():
    with TestClient(main.app) as client:
        client.get("/health")  # deixa o loop de eventos processar a task


def test_lifespan_nao_inicia_o_sync_por_padrao(fake_sync_loop):
    _boot()

    assert fake_sync_loop["started"] == 0


def test_lifespan_inicia_e_cancela_o_sync_quando_habilitado(
    fake_sync_loop, monkeypatch
):
    monkeypatch.setattr(main.settings, "crm_sync_enabled", True)
    monkeypatch.setattr(main.settings, "crm_token", "tok")
    monkeypatch.setattr(main.settings, "geocoding_api_key", "key")

    _boot()

    assert fake_sync_loop["started"] == 1
    assert fake_sync_loop["cancelled"]


def test_lifespan_nao_inicia_o_sync_sem_chaves_e_loga_o_erro(
    fake_sync_loop, monkeypatch, caplog
):
    monkeypatch.setattr(main.settings, "crm_sync_enabled", True)
    monkeypatch.setattr(main.settings, "crm_token", "")
    monkeypatch.setattr(main.settings, "geocoding_api_key", "")

    with caplog.at_level("ERROR", logger="uvicorn.error.crm_sync"):
        _boot()

    assert fake_sync_loop["started"] == 0
    assert "não iniciada" in caplog.text
