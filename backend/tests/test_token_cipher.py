import pytest
from cryptography.fernet import Fernet

from app.errors import TokenCipherError
from app.services.token_cipher import TokenCipher


def test_cifra_e_decifra_ida_e_volta():
    cipher = TokenCipher(Fernet.generate_key().decode())

    encrypted = cipher.encrypt("pat-na1-segredo")

    assert encrypted != "pat-na1-segredo"
    assert "segredo" not in encrypted
    assert cipher.decrypt(encrypted) == "pat-na1-segredo"


def test_chave_diferente_nao_decifra():
    encrypted = TokenCipher(Fernet.generate_key().decode()).encrypt("token")

    with pytest.raises(TokenCipherError):
        TokenCipher(Fernet.generate_key().decode()).decrypt(encrypted)


def test_sem_chave_ou_chave_invalida_falha_cedo():
    with pytest.raises(TokenCipherError):
        TokenCipher("")
    with pytest.raises(TokenCipherError):
        TokenCipher("nao-e-uma-chave-fernet")
