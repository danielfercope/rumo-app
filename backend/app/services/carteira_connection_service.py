"""Casos de uso da conexão de uma organização com o CRM dela: validar o token,
prévia do que será importado, conectar, sincronizar agora e desconectar. Os
endpoints de main.py só traduzem HTTP <-> estes métodos.

Só o ADMIN da organização conecta/desconecta/sincroniza. O token do CRM só vai
pro banco (cifrado) quando o usuário confirma em `connect`; validar e ver a
prévia são sem estado."""

import asyncio
import logging
from collections.abc import Coroutine
from contextlib import aclosing

from ..errors import (
    ConnectionNotFoundError,
    InvalidMappingError,
    NotGroupAdminError,
    SyncInProgressError,
)
from .carteira_sync_service import CarteiraSyncService, SyncResult
from .crm_connector import (
    ConnectorFactory,
    CrmMapping,
    CrmProperty,
    build_connector,
)
from .postgrest_client import PostgrestClient
from .priority_service import PriorityService
from .token_cipher import TokenCipher

logger = logging.getLogger("uvicorn.error.carteira_sync")

# A prévia lê o CRM inteiro; limita pra não prender a requisição numa base
# enorme (100 empresas por página → no máx. 5.000).
PREVIEW_MAX_PAGES = 50


class CarteiraConnectionService:
    def __init__(
        self,
        db: PostgrestClient,
        cipher: TokenCipher,
        sync: CarteiraSyncService,
        connector_factory: ConnectorFactory = build_connector,
        priority: "PriorityService | None" = None,
    ) -> None:
        self._priority = priority
        self._db = db
        self._cipher = cipher
        self._sync = sync
        self._connector_factory = connector_factory
        self._tasks: set[asyncio.Task] = set()

    # ─── Autorização ────────────────────────────────────────────────────

    async def _require_admin(self, uid: str, group_id: str) -> None:
        rows = await self._db.select(
            "group_members",
            {
                "group_id": f"eq.{group_id}",
                "user_id": f"eq.{uid}",
                "role": "eq.admin",
                "select": "user_id",
            },
        )
        if not rows:
            raise NotGroupAdminError(
                "Apenas administradores da organização podem gerenciar o CRM."
            )

    # ─── Validar e pré-visualizar (sem gravar nada) ─────────────────────

    async def validate(
        self, uid: str, group_id: str, provedor: str, token: str
    ) -> list[CrmProperty]:
        """Confere o token no CRM e devolve as propriedades de empresa, pra o
        usuário escolher qual é o CNPJ e qual é o estágio."""
        await self._require_admin(uid, group_id)
        connector = self._connector_factory(provedor, token)
        try:
            await connector.validate()
            return await connector.list_properties()
        finally:
            await connector.aclose()

    async def preview(
        self, uid: str, group_id: str, provedor: str, token: str, mapeamento: dict
    ) -> dict:
        await self._require_admin(uid, group_id)
        mapping = CrmMapping.from_json(mapeamento)
        connector = self._connector_factory(provedor, token)
        try:
            await self._check_mapping(connector, mapping)
            result = SyncResult()
            por_status = {"cliente": 0, "lead": 0, "perdido": 0}
            pages = 0
            truncado = False
            async with aclosing(connector.fetch_changes(None, mapping)) as stream:
                async for records in stream:
                    result.lidas += len(records)
                    for item in self._sync.items_from(records, mapping, result):
                        por_status[item.status] += 1
                    pages += 1
                    if pages >= PREVIEW_MAX_PAGES:
                        truncado = True
                        break
        finally:
            await connector.aclose()
        return {
            "total_com_cnpj": result.lidas,
            "validos": sum(por_status.values()),
            "cnpj_invalido": result.ignoradas,
            "por_status": por_status,
            "truncado": truncado,
        }

    # ─── Conectar / sincronizar / desconectar ───────────────────────────

    async def connect(
        self, uid: str, group_id: str, provedor: str, token: str, mapeamento: dict
    ) -> dict:
        """Grava a conexão (token cifrado) e dispara a carga inicial em segundo
        plano. Reconectar (novo token ou novo mapeamento) zera a marca d'água
        e refaz a leitura completa — é idempotente e corrige os status."""
        await self._require_admin(uid, group_id)
        mapping = CrmMapping.from_json(mapeamento)
        connector = self._connector_factory(provedor, token)
        try:
            await connector.validate()
            await self._check_mapping(connector, mapping)
        finally:
            await connector.aclose()

        existing = await self._find_conexao(group_id)
        if existing and self._sync.is_running(existing["id"]):
            raise SyncInProgressError(
                "Há uma sincronização em andamento; tente de novo em instantes."
            )

        await self._db.upsert(
            "crm_conexoes",
            [
                {
                    "group_id": group_id,
                    "provedor": provedor,
                    "token_cifrado": self._cipher.encrypt(token),
                    "mapeamento": mapeamento,
                    "situacao": "pendente",
                    "ultimo_erro": None,
                    "ultima_modificacao_crm": None,
                    "ultima_sincronizacao": None,
                }
            ],
            on_conflict="group_id",
        )
        conexao = await self._find_conexao(group_id)
        self._run_in_background(self._sync.sync_connection(conexao))
        return {"conexao_id": conexao["id"], "situacao": "pendente"}

    async def sync_now(self, uid: str, group_id: str) -> dict:
        await self._require_admin(uid, group_id)
        conexao = await self._find_conexao(group_id)
        if conexao is None:
            raise ConnectionNotFoundError("Esta organização ainda não conectou um CRM.")
        if self._sync.is_running(conexao["id"]):
            raise SyncInProgressError("Já há uma sincronização em andamento.")
        self._run_in_background(self._sync.sync_connection(conexao))
        return {"conexao_id": conexao["id"]}

    async def disconnect(
        self, uid: str, group_id: str, apagar_carteira: bool = False
    ) -> None:
        """Apaga a conexão (e, por cascade, a fila de pendências dela; o
        histórico em `sincronizacoes` fica, com conexao_id nulo).
        `apagar_carteira` remove também as linhas que vieram do CRM — as
        empresas em `companies` ficam: são dado público e compartilhado."""
        await self._require_admin(uid, group_id)
        conexao = await self._find_conexao(group_id)
        if conexao is None:
            raise ConnectionNotFoundError("Esta organização ainda não conectou um CRM.")
        if self._sync.is_running(conexao["id"]):
            raise SyncInProgressError(
                "Há uma sincronização em andamento; tente de novo em instantes."
            )
        if apagar_carteira:
            await self._db.delete(
                "carteira_empresas",
                {"group_id": f"eq.{group_id}", "origem": "eq.crm"},
            )
            # A prioridade foi calculada sobre essa carteira: sem ela, o
            # resultado guardado ficaria apontando pra empresas que saíram.
            if self._priority is not None:
                await self._priority.clear(group_id)
        await self._db.delete("crm_conexoes", {"id": f"eq.{conexao['id']}"})

    # ─── Auxiliares ─────────────────────────────────────────────────────

    async def _find_conexao(self, group_id: str) -> dict | None:
        rows = await self._db.select(
            "crm_conexoes", {"group_id": f"eq.{group_id}", "select": "*"}
        )
        return rows[0] if rows else None

    @staticmethod
    async def _check_mapping(connector, mapping: CrmMapping) -> None:
        names = {p.name for p in await connector.list_properties()}
        missing = [
            n for n in (mapping.campo_cnpj, mapping.campo_status) if n not in names
        ]
        if missing:
            raise InvalidMappingError(
                "Propriedade(s) não encontrada(s) no CRM: " + ", ".join(missing)
            )

    def _run_in_background(self, coro: Coroutine) -> None:
        # Guarda a referência: o loop só mantém referência fraca às tasks.
        task = asyncio.create_task(coro)
        self._tasks.add(task)

        def _done(t: asyncio.Task) -> None:
            self._tasks.discard(t)
            if not t.cancelled() and t.exception() is not None:
                logger.error(
                    "Sincronização em segundo plano falhou", exc_info=t.exception()
                )

        task.add_done_callback(_done)
