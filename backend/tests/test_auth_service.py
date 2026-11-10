import jwt
import pytest

from app.config import settings
from app.errors import UnauthenticatedError
from app.services import auth_service as auth_module
from app.services.auth_service import AuthService


@pytest.fixture
def service():
    return AuthService()


@pytest.mark.parametrize("header", [None, "", "Basic abc", "abc"])
def test_header_ausente_ou_mal_formatado(service, header):
    with pytest.raises(UnauthenticatedError, match="ausente ou mal formatado"):
        service.exchange_token(header)


def test_token_valido_vira_token_interno_com_uid_e_email(service, monkeypatch):
    monkeypatch.setattr(
        auth_module,
        "verify_firebase_token",
        lambda token: {"uid": "uid-1", "email": "ana@x.com"} if token == "t0k" else {},
    )

    result = service.exchange_token("Bearer  t0k ")

    claims = jwt.decode(result["token"], settings.internal_jwt_secret, algorithms=["HS256"])
    assert claims["sub"] == "uid-1"
    assert claims["email"] == "ana@x.com"
    assert claims["role"] == "web_user"
    assert result["expires_at"] == claims["exp"]


def test_token_sem_email_e_aceito(service, monkeypatch):
    monkeypatch.setattr(auth_module, "verify_firebase_token", lambda t: {"uid": "u"})

    result = service.exchange_token("Bearer x")

    claims = jwt.decode(result["token"], settings.internal_jwt_secret, algorithms=["HS256"])
    assert claims["email"] is None


def test_token_invalido_do_firebase(service, monkeypatch):
    def boom(token):
        raise ValueError("expirado")

    monkeypatch.setattr(auth_module, "verify_firebase_token", boom)

    with pytest.raises(UnauthenticatedError, match="inválido: expirado"):
        service.exchange_token("Bearer x")


# ─── uid_from_internal_token (identidade nos endpoints /carteira) ───────


def test_uid_do_token_interno_de_usuario(service):
    from app.internal_token import mint_internal_token

    token = mint_internal_token("uid-9")["token"]

    assert service.uid_from_internal_token(f"Bearer {token}") == "uid-9"


@pytest.mark.parametrize("header", [None, "", "Basic abc", "abc"])
def test_uid_exige_header_bearer(service, header):
    with pytest.raises(UnauthenticatedError, match="ausente ou mal formatado"):
        service.uid_from_internal_token(header)


def test_uid_recusa_assinatura_errada_e_expirado(service, monkeypatch):
    forged = jwt.encode(
        {"sub": "uid-1", "role": "web_user"}, "outro-segredo", algorithm="HS256"
    )
    with pytest.raises(UnauthenticatedError):
        service.uid_from_internal_token(f"Bearer {forged}")

    expired = jwt.encode(
        {"sub": "uid-1", "role": "web_user", "exp": 1},
        settings.internal_jwt_secret,
        algorithm="HS256",
    )
    with pytest.raises(UnauthenticatedError):
        service.uid_from_internal_token(f"Bearer {expired}")


def test_uid_recusa_papel_que_nao_e_de_usuario(service):
    from app.internal_token import mint_internal_token

    job = mint_internal_token("crm-sync", role="crm_sync")["token"]

    with pytest.raises(UnauthenticatedError, match="identidade"):
        service.uid_from_internal_token(f"Bearer {job}")
