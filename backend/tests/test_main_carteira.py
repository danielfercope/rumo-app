import pytest
from fastapi.testclient import TestClient

from app import main
from app.errors import (
    ConnectionNotFoundError,
    InvalidCrmTokenError,
    InvalidMappingError,
    NotGroupAdminError,
    SyncInProgressError,
    UpstreamIntegrationError,
)
from app.internal_token import mint_internal_token
from app.services.crm_connector import CrmProperty

GROUP = "00000000-0000-0000-0000-00000000000a"
BODY = {"group_id": GROUP, "provedor": "hubspot", "token": "pat-segredo"}
MAPEAMENTO = {
    "campo_cnpj": "cnpj",
    "campo_status": "lifecyclestage",
    "status": {"cliente": ["customer"], "perdido": []},
}


class FakeService:
    def __init__(self, error=None):
        self.error = error
        self.calls: list[tuple] = []

    async def _do(self, name, *args, result=None):
        self.calls.append((name, *args))
        if self.error:
            raise self.error
        return result

    async def validate(self, uid, group_id, provedor, token):
        return await self._do(
            "validate", uid, group_id, provedor, token,
            result=[CrmProperty("cnpj", "CNPJ", "string")],
        )

    async def preview(self, uid, group_id, provedor, token, mapeamento):
        return await self._do(
            "preview", uid, group_id, mapeamento, result={"validos": 3}
        )

    async def connect(self, uid, group_id, provedor, token, mapeamento):
        return await self._do(
            "connect", uid, group_id, mapeamento,
            result={"conexao_id": "c1", "situacao": "pendente"},
        )

    async def sync_now(self, uid, group_id):
        return await self._do("sync_now", uid, group_id, result={"conexao_id": "c1"})

    async def disconnect(self, uid, group_id, apagar_carteira=False):
        await self._do("disconnect", uid, group_id, apagar_carteira)


@pytest.fixture
def client():
    return TestClient(main.app)


@pytest.fixture
def auth():
    token = mint_internal_token("uid-1")["token"]
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def service(monkeypatch):
    fake = FakeService()
    monkeypatch.setattr(main, "carteira_connection_service", fake)
    return fake


# ─── Autenticação ───────────────────────────────────────────────────────

ROTAS = [
    ("post", "/carteira/conexao/validar", {"json": BODY}),
    ("post", "/carteira/conexao/previa", {"json": {**BODY, "mapeamento": MAPEAMENTO}}),
    ("put", "/carteira/conexao", {"json": {**BODY, "mapeamento": MAPEAMENTO}}),
    ("post", f"/carteira/conexao/sincronizar?group_id={GROUP}", {}),
    ("delete", f"/carteira/conexao?group_id={GROUP}", {}),
]


@pytest.mark.parametrize("method, path, kwargs", ROTAS)
def test_rotas_exigem_token(client, service, method, path, kwargs):
    assert getattr(client, method)(path, **kwargs).status_code == 422  # sem header
    ruim = {"Authorization": "Bearer lixo"}
    response = getattr(client, method)(path, headers=ruim, **kwargs)
    assert response.status_code == 401
    assert service.calls == []


def test_token_do_job_nao_serve_de_identidade(client, service):
    job = mint_internal_token("crm-sync", role="crm_sync")["token"]
    response = client.post(
        "/carteira/conexao/validar", json=BODY,
        headers={"Authorization": f"Bearer {job}"},
    )
    assert response.status_code == 401


# ─── Caminho feliz ──────────────────────────────────────────────────────


def test_validar(client, service, auth):
    response = client.post("/carteira/conexao/validar", json=BODY, headers=auth)

    assert response.status_code == 200
    assert response.json() == {
        "propriedades": [{"name": "cnpj", "label": "CNPJ", "type": "string"}]
    }
    assert service.calls == [("validate", "uid-1", GROUP, "hubspot", "pat-segredo")]


def test_previa_repassa_o_mapeamento(client, service, auth):
    response = client.post(
        "/carteira/conexao/previa",
        json={**BODY, "mapeamento": MAPEAMENTO},
        headers=auth,
    )

    assert response.json() == {"validos": 3}
    assert service.calls[0][3]["campo_cnpj"] == "cnpj"


def test_conectar_responde_202(client, service, auth):
    response = client.put(
        "/carteira/conexao", json={**BODY, "mapeamento": MAPEAMENTO}, headers=auth
    )

    assert response.status_code == 202
    assert response.json() == {"conexao_id": "c1", "situacao": "pendente"}


def test_sincronizar_e_desconectar(client, service, auth):
    r1 = client.post(f"/carteira/conexao/sincronizar?group_id={GROUP}", headers=auth)
    r2 = client.delete(
        f"/carteira/conexao?group_id={GROUP}&apagar_carteira=true", headers=auth
    )

    assert r1.status_code == 202
    assert r2.status_code == 204
    assert ("disconnect", "uid-1", GROUP, True) in service.calls


# ─── Erros ──────────────────────────────────────────────────────────────


@pytest.mark.parametrize(
    "error, status",
    [
        (NotGroupAdminError("só admin"), 403),
        (ConnectionNotFoundError("sem conexão"), 404),
        (SyncInProgressError("em andamento"), 409),
        (InvalidCrmTokenError("token recusado"), 400),
        (InvalidMappingError("campo ruim"), 400),
        (UpstreamIntegrationError("crm fora"), 502),
    ],
)
def test_erros_de_dominio_viram_http(client, auth, monkeypatch, error, status):
    monkeypatch.setattr(main, "carteira_connection_service", FakeService(error))

    response = client.post("/carteira/conexao/validar", json=BODY, headers=auth)

    assert response.status_code == status
    assert response.json()["detail"] == str(error)
    assert "pat-segredo" not in response.text  # o token nunca volta na resposta


def test_sem_chave_de_cifra_responde_503(client, auth, monkeypatch):
    monkeypatch.setattr(main, "carteira_connection_service", None)

    response = client.post("/carteira/conexao/validar", json=BODY, headers=auth)

    assert response.status_code == 503


def test_provedor_desconhecido_e_recusado(client, service, auth):
    response = client.post(
        "/carteira/conexao/validar",
        json={**BODY, "provedor": "pipedrive"},
        headers=auth,
    )
    assert response.status_code == 422
    assert "pat-segredo" not in response.text


def test_422_nao_devolve_o_corpo_com_o_token(client, service, auth):
    # Sem `mapeamento`, o `input` do erro padrão seria o corpo todo (com o token).
    response = client.put("/carteira/conexao", json=BODY, headers=auth)

    assert response.status_code == 422
    assert "pat-segredo" not in response.text
    assert response.json()["detail"][0]["loc"] == ["body", "mapeamento"]
