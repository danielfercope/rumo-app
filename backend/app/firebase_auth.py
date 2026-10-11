import firebase_admin
from firebase_admin import auth as firebase_auth_sdk
from firebase_admin import credentials

from .config import settings

_app: firebase_admin.App | None = None


def get_firebase_app() -> firebase_admin.App:
    global _app
    if _app is None:
        cred = credentials.Certificate(settings.firebase_service_account_path)
        _app = firebase_admin.initialize_app(
            cred, options={"projectId": settings.firebase_project_id}
        )
    return _app


def verify_firebase_token(id_token: str) -> dict:
    """Valida o ID Token do Firebase via Admin SDK (que cuida da busca/rotação
    do JWKS do Google por conta própria). Levanta se o token for inválido/expirado."""
    get_firebase_app()
    return firebase_auth_sdk.verify_id_token(id_token)
