import pytest

from app import firebase_auth


@pytest.fixture(autouse=True)
def reset_app(monkeypatch):
    monkeypatch.setattr(firebase_auth, "_app", None)


def test_get_firebase_app_inicializa_uma_vez_e_reaproveita(monkeypatch):
    certs, inits = [], []
    monkeypatch.setattr(
        firebase_auth.credentials, "Certificate", lambda path: certs.append(path) or "cred"
    )
    monkeypatch.setattr(
        firebase_auth.firebase_admin,
        "initialize_app",
        lambda cred, options: inits.append((cred, options)) or object(),
    )

    first = firebase_auth.get_firebase_app()
    second = firebase_auth.get_firebase_app()

    assert first is second
    assert certs == [firebase_auth.settings.firebase_service_account_path]
    assert inits == [
        ("cred", {"projectId": firebase_auth.settings.firebase_project_id})
    ]


def test_verify_firebase_token_delega_ao_admin_sdk(monkeypatch):
    monkeypatch.setattr(firebase_auth, "get_firebase_app", lambda: None)
    monkeypatch.setattr(
        firebase_auth.firebase_auth_sdk,
        "verify_id_token",
        lambda token: {"uid": f"uid-de-{token}"},
    )

    assert firebase_auth.verify_firebase_token("abc") == {"uid": "uid-de-abc"}
