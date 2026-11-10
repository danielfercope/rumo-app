"""Exceções de domínio dos services — nada aqui depende do FastAPI.
main.py (a camada de rotas) é quem traduz essas exceções em HTTPException."""


class UnauthenticatedError(Exception):
    """Token do Firebase ausente, mal formatado ou inválido."""


class NotImplementedIntegrationError(Exception):
    """Integração externa ainda sem lógica real implementada."""


class CnpjNotFoundError(Exception):
    """CNPJ não encontrado no provedor de consulta de dados cadastrais."""


class InvalidCrmTokenError(Exception):
    """O CRM recusou o token da organização (inválido, revogado ou sem as
    permissões de leitura necessárias)."""


class NotGroupAdminError(Exception):
    """Quem fez a chamada não é administrador da organização."""


class NotGroupMemberError(Exception):
    """Quem fez a chamada não pertence à organização."""


class InvalidMappingError(Exception):
    """O mapeamento de campos aponta pra uma propriedade que não existe no CRM."""


class ConnectionNotFoundError(Exception):
    """A organização ainda não conectou um CRM."""


class SyncInProgressError(Exception):
    """Já há uma sincronização dessa conexão em andamento."""


class TokenCipherError(Exception):
    """Token cifrado ilegível: chave de cifra ausente, trocada ou dado corrompido."""


class CrmCompanyNotFoundError(Exception):
    """Nenhuma empresa no CRM corresponde ao CNPJ informado."""


class UpstreamIntegrationError(Exception):
    """Falha de rede ou de resposta ao chamar uma integração externa."""


class GeocodingNotFoundError(Exception):
    """O provedor de geocodificação não achou coordenadas pro endereço."""
