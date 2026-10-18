from typing import Literal

from pydantic import BaseModel


class CrmRequest(BaseModel):
    action: Literal["getNotesWithOwners", "getContacts", "addContact", "addNote"]
    cnpj: str
    nome: str | None = None
    telefone: str | None = None
    email: str | None = None
    noteText: str | None = None


class CompanyLookupRequest(BaseModel):
    cnpj: str
