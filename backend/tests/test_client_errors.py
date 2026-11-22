import json
import logging

import pytest
from fastapi.testclient import TestClient

from app import main
from app.internal_token import mint_internal_token
from app.services.client_error_service import ClientErrorService


@pytest.fixture
def client(monkeypatch):
    # limite novo por teste: o serviço guarda contagem entre chamadas
    monkeypatch.setattr(main, "client_error_service", ClientErrorService())
    return TestClient(main.app)


def _logged(caplog) -> list[dict]:
    out = []
    for rec in caplog.records:
        if rec.name == "uvicorn.error.client":
            msg = rec.getMessage()
            assert msg.startswith("client_error ")
            out.append(json.loads(msg.removeprefix("client_error ")))
    return out


def test_relato_anonimo_vira_uma_linha_json(client, caplog):
    caplog.set_level(logging.ERROR, logger="uvicorn.error.client")
    resp = client.post(
        "/client-errors",
        json={"message": "boom", "stack": "linha 1\nlinha 2", "fatal": True},
    )
    assert resp.status_code == 204
    [entry] = _logged(caplog)
    assert entry["uid"] is None
    assert entry["message"] == "boom"
    assert entry["fatal"] is True
    # a pilha fica numa linha só (JSON), sem quebrar o evento no CloudWatch
    [rec] = [r for r in caplog.records if r.name == "uvicorn.error.client"]
    assert "\n" not in rec.getMessage()


def test_relato_com_login_grava_o_uid(client, caplog):
    caplog.set_level(logging.ERROR, logger="uvicorn.error.client")
    token = mint_internal_token("uid-42")["token"]
    resp = client.post(
        "/client-errors",
        json={"message": "x"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert resp.status_code == 204
    assert _logged(caplog)[0]["uid"] == "uid-42"


def test_token_invalido_nao_bloqueia_o_relato(client, caplog):
    caplog.set_level(logging.ERROR, logger="uvicorn.error.client")
    resp = client.post(
        "/client-errors",
        json={"message": "x"},
        headers={"Authorization": "Bearer lixo"},
    )
    assert resp.status_code == 204
    assert _logged(caplog)[0]["uid"] is None


def test_campos_grandes_demais_sao_recusados(client):
    resp = client.post("/client-errors", json={"message": "x" * 2001})
    assert resp.status_code == 422
    resp = client.post("/client-errors", json={"message": ""})
    assert resp.status_code == 422


def test_limite_por_cliente(client):
    for _ in range(20):
        assert client.post("/client-errors", json={"message": "x"}).status_code == 204
    assert client.post("/client-errors", json={"message": "x"}).status_code == 429
    # outro IP (atrás do Caddy) tem o próprio limite
    resp = client.post(
        "/client-errors",
        json={"message": "x"},
        headers={"X-Forwarded-For": "203.0.113.9"},
    )
    assert resp.status_code == 204


def test_limite_libera_depois_da_janela():
    agora = [0.0]
    svc = ClientErrorService(max_per_window=2, window_seconds=60, clock=lambda: agora[0])
    assert svc.allow("a") and svc.allow("a")
    assert not svc.allow("a")
    agora[0] = 60.0
    assert svc.allow("a")


def test_numero_de_clientes_acompanhados_e_limitado(monkeypatch):
    from app.services import client_error_service as mod

    monkeypatch.setattr(mod, "MAX_TRACKED_CLIENTS", 3)
    svc = ClientErrorService(max_per_window=5, clock=lambda: 0.0)
    for key in ("a", "b", "c", "d", "e"):
        assert svc.allow(key)
    assert len(svc._hits) <= 3
