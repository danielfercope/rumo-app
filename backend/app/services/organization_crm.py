"""Qual CRM atende as notas e contatos de uma organização.

1. A organização conectou o próprio CRM (`crm_conexoes`): usa o token dela
   (cifrado no banco) e o ID da empresa no CRM que a sincronização já gravou em
   `carteira_empresas.crm_object_id` — sem busca por CNPJ. Empresa sem esse ID
   (cadastro manual) é procurada pela propriedade de CNPJ do mapeamento; se
   não estiver lá, a primeira nota ou contato cria a empresa no CRM e guarda o
   ID na carteira.
2. Sem conexão não há CRM: `CrmNotAvailableError`. Não existe conta global —
   organização sem CRM nem chega aqui (AccessService.require_crm).

Quem chama já conferiu que o usuário é membro e que o CNPJ está na carteira."""

import re
from contextlib import asynccontextmanager
from functools import partial
from typing import AsyncIterator

from ..errors import CrmNotAvailableError
from .crm_connector import CrmMapping
from .crm_service import CrmService
from .postgrest_client import PostgrestClient
from .token_cipher import TokenCipher


class OrganizationCrm:
    def __init__(
        self,
        db: PostgrestClient,
        cipher: TokenCipher | None,
    ) -> None:
        self._db = db
        self._cipher = cipher

    @asynccontextmanager
    async def open(
        self, group_id: str, cnpj: str
    ) -> AsyncIterator[tuple[CrmService, str | None]]:
        """(serviço, id da empresa no CRM ou None pra procurar pelo CNPJ)."""
        conexao = await self._find_connection(group_id)
        if conexao is not None:
            if conexao.get("provedor") != "hubspot" or self._cipher is None:
                raise CrmNotAvailableError(
                    "Notas e contatos não estão disponíveis para o CRM desta organização."
                )
            token = self._cipher.decrypt(conexao["token_cifrado"])
            mapping = CrmMapping.from_json(conexao.get("mapeamento"))
            service = CrmService(
                token=token,
                cnpj_property=mapping.campo_cnpj,
                on_company_missing=partial(
                    self._create_in_crm, group_id, mapping.campo_cnpj
                ),
            )
            try:
                yield service, await self._crm_object_id(group_id, cnpj)
            finally:
                await service.aclose()
            return

        raise CrmNotAvailableError(
            "Esta organização ainda não conectou um CRM. Um administrador pode "
            "conectar na aba Organização."
        )

    async def _find_connection(self, group_id: str) -> dict | None:
        rows = await self._db.select(
            "crm_conexoes",
            {
                "group_id": f"eq.{group_id}",
                "select": "provedor,token_cifrado,mapeamento",
                "limit": "1",
            },
        )
        return rows[0] if rows else None

    async def _crm_object_id(self, group_id: str, cnpj: str) -> str | None:
        digits = re.sub(r"\D", "", cnpj or "")
        rows = await self._db.select(
            "carteira_empresas",
            {
                "group_id": f"eq.{group_id}",
                "companies.cnpj": f"eq.{digits}",
                "select": "crm_object_id,companies!inner(cnpj)",
                "limit": "1",
            },
        )
        return (rows[0].get("crm_object_id") or None) if rows else None

    async def _create_in_crm(
        self, group_id: str, cnpj_property: str, service: CrmService, cnpj: str
    ) -> str | None:
        """Leva ao CRM uma empresa cadastrada no app (que só existe na carteira)
        e grava o ID dela em `carteira_empresas.crm_object_id`."""
        digits = re.sub(r"\D", "", cnpj or "")
        rows = await self._db.select(
            "carteira_empresas",
            {
                "group_id": f"eq.{group_id}",
                "companies.cnpj": f"eq.{digits}",
                "select": (
                    "company_id,companies!inner(cnpj,nome_fantasia,razao_social,"
                    "municipio,uf,telefone_principal)"
                ),
                "limit": "1",
            },
        )
        if not rows:
            return None
        empresa = rows[0]["companies"]
        crm_id = await service.create_company(
            {
                "name": empresa.get("nome_fantasia") or empresa.get("razao_social"),
                cnpj_property: digits,
                "city": empresa.get("municipio"),
                "state": empresa.get("uf"),
                "phone": empresa.get("telefone_principal"),
            }
        )
        await self._db.update(
            "carteira_empresas",
            {
                "group_id": f"eq.{group_id}",
                "company_id": f"eq.{rows[0]['company_id']}",
            },
            {"crm_object_id": crm_id},
        )
        return crm_id
