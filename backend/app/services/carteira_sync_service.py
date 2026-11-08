import asyncio
import logging
import re
import time
import uuid
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime, timezone

from ..config import settings
from ..errors import (
    CnpjNotFoundError,
    GeocodingNotFoundError,
    InvalidCrmTokenError,
    TokenCipherError,
    UpstreamIntegrationError,
)
from .company_lookup_service import CompanyLookupService
from .crm_connector import (
    ConnectorFactory,
    CrmConnector,
    CrmMapping,
    CrmRecord,
    _iso_to_ms,
    build_connector,
)
from .crm_sync_service import build_company_row, build_geocoding_address
from .geocoding_service import GeocodingService
from .postgrest_client import PostgrestClient
from .token_cipher import TokenCipher

# Filho de "uvicorn.error" pra aparecer nos logs do container sem ligar o INFO
# do httpx (cujas URLs podem incluir chaves de API).
logger = logging.getLogger("uvicorn.error.carteira_sync")

MAX_ATTEMPTS = 5
PENDING_BATCH = 25
BACKOFF_BASE_MINUTES = 10
BACKOFF_MAX_MINUTES = 360

def _only_digits(value: str | None) -> str:
    return re.sub(r"\D", "", value or "")


@dataclass
class Item:
    """Uma empresa do CRM a gravar na carteira (já com CNPJ válido e status mapeado)."""

    external_id: str
    cnpj: str
    status: str
    attempts: int = 0  # tentativas anteriores (> 0 só vindo de carteira_pendencias)


@dataclass
class SyncResult:
    lidas: int = 0
    novas: int = 0
    atualizadas: int = 0
    sem_mudanca: int = 0
    falhas: int = 0
    ignoradas: int = 0


class CarteiraSyncService:
    """Mantém a carteira (carteira_empresas) de cada organização em dia com o
    CRM dela, usando o token que a organização forneceu.

    Para cada conexão ativa: lê do CRM só o que mudou desde a marca d'água
    (`crm_conexoes.ultima_modificacao_crm`, por data de modificação — assim
    pega também mudança de status, não só empresa nova), garante que cada
    empresa exista em `companies` (global: se outra organização já trouxe o
    CNPJ, não reconsulta BrasilAPI nem Google) e grava o status na carteira.
    Falhas por empresa (CNPJ não achado, sem coordenada, rede) vão pra
    `carteira_pendencias` com backoff; a marca d'água avança além delas."""

    def __init__(
        self,
        db: PostgrestClient,
        lookup: CompanyLookupService,
        geocoder: GeocodingService,
        cipher: TokenCipher,
        connector_factory: ConnectorFactory = build_connector,
        *,
        company_pause: float = 0.2,
        clock: Callable[[], float] = time.time,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._db = db
        self._lookup = lookup
        self._geocoder = geocoder
        self._cipher = cipher
        self._connector_factory = connector_factory
        self._company_pause = company_pause
        self._clock = clock
        self._sleep = sleep
        self._locks: dict[str, asyncio.Lock] = {}

    async def run_forever(self) -> None:
        interval = settings.crm_sync_interval_seconds
        while True:
            try:
                await self.run_cycle()
            except Exception:
                # Um ciclo ruim (banco reiniciando) não pode derrubar o job
                # nem o app: o próximo ciclo tenta de novo.
                logger.exception("Falha no ciclo de sincronização das carteiras")
            await self._sleep(interval)

    async def run_cycle(self) -> dict[str, SyncResult]:
        conexoes = await self._db.select(
            "crm_conexoes", {"situacao": "eq.ativa", "select": "*"}
        )
        results: dict[str, SyncResult] = {}
        # Em sequência, de propósito: a instância é pequena e cada conta de
        # CRM tem o próprio limite de requisições.
        for conexao in conexoes:
            results[conexao["id"]] = await self.sync_connection(conexao)
        return results

    def is_running(self, conexao_id: str) -> bool:
        lock = self._locks.get(conexao_id)
        return lock is not None and lock.locked()

    async def sync_connection(self, conexao: dict) -> SyncResult:
        """Sincroniza uma conexão. Sem marca d'água é a carga inicial; com ela,
        incremental. Ao concluir marca a conexão como 'ativa' — por isso serve
        também pra rodar a carga inicial de uma conexão recém-criada."""
        lock = self._locks.setdefault(conexao["id"], asyncio.Lock())
        async with lock:
            return await self._sync_locked(conexao)

    async def _sync_locked(self, conexao: dict) -> SyncResult:
        result = SyncResult()
        watermark = conexao.get("ultima_modificacao_crm")
        tipo = "incremental" if watermark else "carga_inicial"
        started_at = self._now_iso()
        sync_id = str(uuid.uuid4())
        if tipo == "carga_inicial":
            # A carga inicial é longa: grava o log já no começo pra a tela de
            # status mostrar "em andamento". O incremental só deixa log se
            # houver novidade ou erro (senão seriam ~144 linhas/dia por conexão).
            await self._db.insert(
                "sincronizacoes",
                [self._log_row(sync_id, conexao, tipo, started_at)],
            )

        situacao = conexao.get("situacao", "pendente")
        erro: str | None = None
        try:
            token = self._cipher.decrypt(conexao["token_cifrado"])
            connector = self._connector_factory(conexao["provedor"], token)
            try:
                await self._pull(conexao, connector, watermark, result)
            finally:
                await connector.aclose()
            situacao = "ativa"
        except InvalidCrmTokenError as exc:
            situacao, erro = "erro", str(exc)
        except TokenCipherError as exc:
            situacao, erro = "erro", str(exc)
        except UpstreamIntegrationError as exc:
            # Falha transitória (CRM/rede): mantém a situação; o progresso já
            # gravado (marca d'água por página) não se perde.
            erro = str(exc)
        except Exception as exc:
            logger.exception("Falha inesperada na conexão %s", conexao["id"])
            erro = f"{type(exc).__name__}: {exc}"

        await self._finish(conexao, sync_id, tipo, started_at, situacao, erro, result)
        logger.info(
            "Carteira %s (%s): %s%s",
            conexao["group_id"],
            tipo,
            result,
            f" — erro: {erro}" if erro else "",
        )
        return result

    # ─── Leitura do CRM ─────────────────────────────────────────────────

    async def _pull(
        self,
        conexao: dict,
        connector: CrmConnector,
        watermark: str | None,
        result: SyncResult,
    ) -> None:
        mapping = CrmMapping.from_json(conexao.get("mapeamento"))
        since_ms = None
        if watermark:
            # Sobreposição: o Search do HubSpot demora a indexar mudanças, então
            # reconsulta uma janela recente (é idempotente: só grava o que mudou).
            since_ms = _iso_to_ms(watermark) - settings.crm_sync_overlap_minutes * 60_000

        saved_ms = _iso_to_ms(watermark) if watermark else 0
        async for records in connector.fetch_changes(since_ms, mapping):
            result.lidas += len(records)
            items = self.items_from(records, mapping, result)
            await self._ingest(conexao, items, result)
            # Marca d'água por página: se a carga cair no meio, retoma dali. Só
            # grava quando avança (a janela de sobreposição reconsulta o mesmo
            # registro todo ciclo).
            if records[-1].modified_at_ms > saved_ms:
                saved_ms = records[-1].modified_at_ms
                await self._db.update(
                    "crm_conexoes",
                    {"id": f"eq.{conexao['id']}"},
                    {"ultima_modificacao_crm": self._ms_to_iso(saved_ms)},
                )

        await self._retry_pending(conexao, result)

    @staticmethod
    def items_from(
        records: list[CrmRecord], mapping: CrmMapping, result: SyncResult
    ) -> list[Item]:
        by_cnpj: dict[str, Item] = {}
        for record in records:  # ordem crescente de modificação: o último vence
            cnpj = _only_digits(record.cnpj)
            if len(cnpj) != 14:
                logger.warning(
                    "Empresa %s do CRM ignorada: CNPJ inválido (%r)",
                    record.external_id,
                    record.cnpj,
                )
                result.ignoradas += 1
                continue
            by_cnpj[cnpj] = Item(
                record.external_id, cnpj, mapping.resolve_status(record.status_value)
            )
        return list(by_cnpj.values())

    # ─── Gravação na carteira ───────────────────────────────────────────

    async def _ingest(
        self,
        conexao: dict,
        items: list[Item],
        result: SyncResult,
        *,
        retrying: bool = False,
    ) -> None:
        if not items:
            return
        group_id = conexao["group_id"]

        if not retrying:
            # Empresa que já está na fila só é retentada quando o backoff vence
            # (_retry_pending), não a cada ciclo da janela de sobreposição.
            waiting = await self._pending_ids(conexao, [i.external_id for i in items])
            items = [i for i in items if i.external_id not in waiting]
            if not items:
                return

        company_ids = await self._company_ids_by_cnpj({i.cnpj for i in items})
        current = await self._carteira_by_company(
            group_id, list(company_ids.values())
        )

        rows: list[dict] = []
        done: list[str] = []
        for item in items:
            company_id = company_ids.get(item.cnpj)
            if company_id is None:
                try:
                    company_id = await self._import_company(item.cnpj)
                except (
                    CnpjNotFoundError,
                    GeocodingNotFoundError,
                    UpstreamIntegrationError,
                ) as exc:
                    await self._mark_failed(conexao, item, exc)
                    result.falhas += 1
                    continue
                company_ids[item.cnpj] = company_id

            existing = current.get(company_id)
            if existing is None:
                result.novas += 1
            elif (
                existing["status"] != item.status
                or existing.get("crm_object_id") != item.external_id
            ):
                result.atualizadas += 1
            else:
                result.sem_mudanca += 1
                if retrying:
                    done.append(item.external_id)
                continue

            rows.append(
                {
                    "group_id": group_id,
                    "company_id": company_id,
                    "status": item.status,
                    "origem": "crm",
                    "crm_object_id": item.external_id,
                    "status_atualizado_em": self._now_iso(),
                }
            )
            if retrying:
                done.append(item.external_id)

        if rows:
            await self._db.upsert(
                "carteira_empresas", rows, on_conflict="group_id,company_id"
            )
        if done:
            await self._clear_pending(conexao, done)

    async def _import_company(self, cnpj: str) -> str:
        data = await self._lookup.lookup_cnpj(cnpj)
        geo = await self._geocoder.geocode(build_geocoding_address(data))
        row = build_company_row(data, cnpj, geo.latitude, geo.longitude, geo.precisao)
        # DO NOTHING: se o app (ou outra organização) cadastrou a mesma empresa
        # no meio do caminho, o cadastro dela prevalece.
        await self._db.insert(
            "companies", [row], on_conflict="cnpj", ignore_duplicates=True
        )
        created = await self._db.select(
            "companies", {"cnpj": f"eq.{cnpj}", "select": "id"}
        )
        if self._company_pause:
            await self._sleep(self._company_pause)
        return created[0]["id"]

    async def _company_ids_by_cnpj(self, cnpjs: set[str]) -> dict[str, str]:
        # Um único SELECT indexado (cnpj é UNIQUE) restrito ao lote do CRM.
        rows = await self._db.select(
            "companies",
            {"cnpj": f"in.({','.join(sorted(cnpjs))})", "select": "id,cnpj"},
        )
        return {row["cnpj"]: row["id"] for row in rows}

    async def _carteira_by_company(
        self, group_id: str, company_ids: list[str]
    ) -> dict[str, dict]:
        if not company_ids:
            return {}
        rows = await self._db.select(
            "carteira_empresas",
            {
                "group_id": f"eq.{group_id}",
                "company_id": f"in.({','.join(company_ids)})",
                "select": "company_id,status,crm_object_id",
            },
        )
        return {row["company_id"]: row for row in rows}

    # ─── Pendências ─────────────────────────────────────────────────────

    async def _retry_pending(self, conexao: dict, result: SyncResult) -> None:
        rows = await self._db.select(
            "carteira_pendencias",
            {
                "conexao_id": f"eq.{conexao['id']}",
                "next_retry_at": f"lte.{self._now_iso()}",
                "attempts": f"lt.{MAX_ATTEMPTS}",
                "order": "next_retry_at.asc",
                "limit": str(PENDING_BATCH),
                "select": "crm_object_id,cnpj,status,attempts",
            },
        )
        if not rows:
            return
        items = [
            Item(r["crm_object_id"], r["cnpj"], r["status"], r["attempts"])
            for r in rows
        ]
        # As que dão certo saem da fila dentro de _ingest; as que falham de
        # novo são regravadas por _mark_failed (attempts + 1).
        await self._ingest(conexao, items, result, retrying=True)

    async def _pending_ids(self, conexao: dict, external_ids: list[str]) -> set[str]:
        rows = await self._db.select(
            "carteira_pendencias",
            {
                "conexao_id": f"eq.{conexao['id']}",
                "crm_object_id": f"in.({','.join(external_ids)})",
                "select": "crm_object_id",
            },
        )
        return {row["crm_object_id"] for row in rows}

    async def _mark_failed(self, conexao: dict, item: Item, exc: Exception) -> None:
        attempts = item.attempts + 1
        backoff = min(BACKOFF_BASE_MINUTES * 2**attempts, BACKOFF_MAX_MINUTES)
        logger.warning(
            "Empresa %s (CNPJ %s) falhou na conexão %s, tentativa %s: %s",
            item.external_id,
            item.cnpj,
            conexao["id"],
            attempts,
            exc,
        )
        await self._db.upsert(
            "carteira_pendencias",
            [
                {
                    "conexao_id": conexao["id"],
                    "crm_object_id": item.external_id,
                    "cnpj": item.cnpj,
                    "status": item.status,
                    "attempts": attempts,
                    "last_error": str(exc)[:500],
                    "next_retry_at": self._iso(self._clock() + backoff * 60),
                }
            ],
            on_conflict="conexao_id,crm_object_id",
        )

    async def _clear_pending(self, conexao: dict, external_ids: list[str]) -> None:
        await self._db.delete(
            "carteira_pendencias",
            {
                "conexao_id": f"eq.{conexao['id']}",
                "crm_object_id": f"in.({','.join(external_ids)})",
            },
        )

    # ─── Encerramento e utilidades ──────────────────────────────────────

    @staticmethod
    def _log_row(sync_id: str, conexao: dict, tipo: str, started_at: str) -> dict:
        return {
            "id": sync_id,
            "group_id": conexao["group_id"],
            "conexao_id": conexao["id"],
            "tipo": tipo,
            "iniciada_em": started_at,
        }

    async def _finish(
        self,
        conexao: dict,
        sync_id: str,
        tipo: str,
        started_at: str,
        situacao: str,
        erro: str | None,
        result: SyncResult,
    ) -> None:
        now = self._now_iso()
        outcome = {
            "situacao": "erro" if erro else "concluida",
            "total_lidas": result.lidas,
            "total_novas": result.novas,
            "total_atualizadas": result.atualizadas,
            "total_falhas": result.falhas,
            "erro": erro,
            "concluida_em": now,
        }
        if tipo == "carga_inicial":
            await self._db.update("sincronizacoes", {"id": f"eq.{sync_id}"}, outcome)
        elif erro or result.novas or result.atualizadas or result.falhas:
            await self._db.insert(
                "sincronizacoes",
                [{**self._log_row(sync_id, conexao, tipo, started_at), **outcome}],
            )
        values: dict = {"situacao": situacao, "ultimo_erro": erro}
        if not erro:
            values["ultima_sincronizacao"] = now
        await self._db.update("crm_conexoes", {"id": f"eq.{conexao['id']}"}, values)

    @staticmethod
    def _iso(epoch_seconds: float) -> str:
        return datetime.fromtimestamp(epoch_seconds, tz=timezone.utc).isoformat()

    def _ms_to_iso(self, epoch_ms: int) -> str:
        return self._iso(epoch_ms / 1000)

    def _now_iso(self) -> str:
        return self._iso(self._clock())
