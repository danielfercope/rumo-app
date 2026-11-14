"""Quem pode ver o quê: tudo é por organização.

O Backend fala com o banco como o papel `crm_sync`, que enxerga todas as
organizações. Por isso, antes de tocar em dado de uma organização (ou numa
integração externa em nome dela), cada rota confere aqui a pertinência do
usuário — a mesma regra que a RLS aplica no acesso direto do app."""

import re

from ..errors import CompanyNotInPortfolioError, NotGroupMemberError
from .postgrest_client import PostgrestClient


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

    async def require_any_organization(self, uid: str) -> None:
        rows = await self._db.select(
            "group_members",
            {"user_id": f"eq.{uid}", "select": "group_id", "limit": "1"},
        )
        if not rows:
            raise NotGroupMemberError(
                "Entre em uma organização para usar este recurso."
            )

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
