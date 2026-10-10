from ..errors import UnauthenticatedError
from ..firebase_auth import verify_firebase_token
from ..internal_token import mint_internal_token


class AuthService:
    """Troca um ID Token do Firebase por um token interno HS256 que o
    PostgREST aceita. Existe porque o PostgREST não busca/atualiza o JWKS
    do Google automaticamente (ver seção 2 do plano de migração)."""

    def exchange_token(self, authorization_header: str | None) -> dict:
        if not authorization_header or not authorization_header.startswith("Bearer "):
            raise UnauthenticatedError("Token do Firebase ausente ou mal formatado")

        id_token = authorization_header.removeprefix("Bearer ").strip()
        try:
            decoded = verify_firebase_token(id_token)
        except Exception as exc:
            raise UnauthenticatedError(f"Token do Firebase inválido: {exc}") from exc

        return mint_internal_token(uid=decoded["uid"], email=decoded.get("email"))
