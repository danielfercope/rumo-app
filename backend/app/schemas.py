from typing import Literal

from pydantic import BaseModel, Field


class CrmRequest(BaseModel):
    # Organização em nome da qual se consulta: o Backend confere que quem chama
    # é membro e que o CNPJ está na carteira dela.
    group_id: str
    action: Literal["getNotesWithOwners", "getContacts", "addContact", "addNote"]
    cnpj: str
    nome: str | None = None
    telefone: str | None = None
    email: str | None = None
    noteText: str | None = None


class CompanyLookupRequest(BaseModel):
    cnpj: str


class StatusMapeamento(BaseModel):
    """Valores da propriedade de estágio que significam cliente/perdido (todo o
    resto é lead)."""

    cliente: list[str] = []
    perdido: list[str] = []


class Mapeamento(BaseModel):
    campo_cnpj: str = Field(min_length=1)
    campo_status: str = Field(min_length=1)
    status: StatusMapeamento = StatusMapeamento()


class CredencialCrm(BaseModel):
    group_id: str
    provedor: Literal["hubspot"] = "hubspot"
    token: str = Field(min_length=1)


class PreviaCarteiraRequest(CredencialCrm):
    mapeamento: Mapeamento


class ConectarCrmRequest(CredencialCrm):
    mapeamento: Mapeamento
