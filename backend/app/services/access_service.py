"""Quem pode ver o quê: tudo é por organização.

O Backend fala com o banco como o papel `crm_sync`, que enxerga todas as
organizações. Por isso, antes de tocar em dado de uma organização (ou numa
integração externa em nome dela), cada rota confere aqui a pertinência do
usuário — a mesma regra que a RLS aplica no acesso direto do app.

Não existe conta ou base global: organização sem CRM conectado
(`crm_conexoes`) não usa o sistema — nem busca, nem cadastro, nem detalhes.
Só os administradores dela conectam o CRM (carteira_connection_service)."""

import re

from ..errors import (
    CompanyNotInPortfolioError,
    CrmNotAvailableError,
    NotGroupMemberError,
)
from .postgrest_client import PostgrestClient


_SEM_CRM = (
    "Esta organização ainda não conectou um CRM. Um administrador pode "
    "conectar na aba Organização."
)


class AccessService:
    def __init__(self, db: PostgrestClient) -> None:
        self._db = db

    async def require_member(self, uid: str, group_id: str) -> None:
        rows = await self._db.select(
            "group_members",
            {"group_id": f"eq.{group_id}", "user_id": f"eq.{uid}", "select": "user_id"},
        )
        if not rows:
            raise NotGroupMemberError("Você não pertence a esta organização.")

    async def require_crm(self, group_id: str) -> None:
        rows = await self._db.select(
            "crm_conexoes",
            {"group_id": f"eq.{group_id}", "select": "group_id", "limit": "1"},
        )
        if not rows:
            raise CrmNotAvailableError(_SEM_CRM)

    async def require_any_organization(self, uid: str) -> None:
        """Membro de alguma organização que tenha CRM conectado."""
        rows = await self._db.select(
            "group_members", {"user_id": f"eq.{uid}", "select": "group_id"}
        )
        if not rows:
            raise NotGroupMemberError(
                "Entre em uma organização para usar este recurso."
            )
        ids = ",".join(r["group_id"] for r in rows)
        conectadas = await self._db.select(
            "crm_conexoes",
            {"group_id": f"in.({ids})", "select": "group_id", "limit": "1"},
        )
        if not conectadas:
            raise NotGroupMemberError(_SEM_CRM)

    async def require_cnpj_in_portfolio(self, group_id: str, cnpj: str) -> None:
        digits = re.sub(r"\D", "", cnpj or "")
        rows = await self._db.select(
            "carteira_empresas",
            {
                "group_id": f"eq.{group_id}",
                "companies.cnpj": f"eq.{digits}",
                "select": "company_id,companies!inner(cnpj)",
                "limit": "1",
            },
        )
        if not digits or not rows:
            raise CompanyNotInPortfolioError(
                "Empresa não encontrada na carteira desta organização."
            )
