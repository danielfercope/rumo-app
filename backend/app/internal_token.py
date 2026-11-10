import time

import jwt

from .config import settings


def mint_internal_token(uid: str, email: str | None = None, role: str = "web_user") -> dict:
    """Emite o token interno (HS256, segredo fixo) que o PostgREST aceita —
    nunca precisa de reload, diferente de validar o JWKS do Firebase direto.

    O claim "email" vem do token do Firebase já verificado pelo Admin SDK,
    então é confiável dentro do Postgres (ex.: usado pela função
    claim_or_create_profile, que reivindica um perfil migrado pelo e-mail)."""
    now = int(time.time())
    exp = now + settings.internal_jwt_ttl_seconds
    payload = {"sub": uid, "email": email, "role": role, "iat": now, "exp": exp}
    token = jwt.encode(payload, settings.internal_jwt_secret, algorithm="HS256")
    return {"token": token, "expires_at": exp}
