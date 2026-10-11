"""Exceções de domínio dos services — nada aqui depende do FastAPI.
main.py (a camada de rotas) é quem traduz essas exceções em HTTPException."""


class UnauthenticatedError(Exception):
    """Token do Firebase ausente, mal formatado ou inválido."""


class NotImplementedIntegrationError(Exception):
    """Integração externa ainda sem lógica real implementada."""
