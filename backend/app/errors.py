"""Exceções de domínio dos services — nada aqui depende do FastAPI.
main.py (a camada de rotas) é quem traduz essas exceções em HTTPException."""


class UnauthenticatedError(Exception):
    """Token do Firebase ausente, mal formatado ou inválido."""


class NotImplementedIntegrationError(Exception):
    """Integração externa ainda sem lógica real implementada."""


class CnpjNotFoundError(Exception):
    """CNPJ não encontrado no provedor de consulta de dados cadastrais."""


class CrmCompanyNotFoundError(Exception):
    """Nenhuma empresa no CRM corresponde ao CNPJ informado."""


class UpstreamIntegrationError(Exception):
    """Falha de rede ou de resposta ao chamar uma integração externa."""
