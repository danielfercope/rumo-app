from cryptography.fernet import Fernet, InvalidToken

from ..config import settings
from ..errors import TokenCipherError


class TokenCipher:
    """Cifra o token de CRM de cada organização antes de ir pro banco
    (crm_conexoes.token_cifrado). A chave vive só no ambiente do Backend, então
    um dump do banco sozinho não expõe nenhum token."""

    def __init__(self, key: str | None = None) -> None:
        raw = key if key is not None else settings.crm_token_encryption_key
        if not raw:
            raise TokenCipherError(
                "CRM_TOKEN_ENCRYPTION_KEY não configurada — não dá pra cifrar "
                "nem ler tokens de CRM."
            )
        try:
            self._fernet = Fernet(raw.encode())
        except ValueError as exc:
            raise TokenCipherError(
                "CRM_TOKEN_ENCRYPTION_KEY inválida (esperado urlsafe base64 de 32 bytes)."
            ) from exc

    def encrypt(self, token: str) -> str:
        return self._fernet.encrypt(token.encode()).decode()

    def decrypt(self, encrypted: str) -> str:
        try:
            return self._fernet.decrypt(encrypted.encode()).decode()
        except InvalidToken as exc:
            raise TokenCipherError(
                "Token de CRM ilegível: a chave de cifra mudou ou o dado está "
                "corrompido. A organização precisa reconectar o CRM."
            ) from exc
