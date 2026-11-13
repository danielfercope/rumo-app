import asyncio
import logging
import re
import time
from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import datetime, timezone

from ..config import settings
from ..errors import (
    CnpjNotFoundError,
    GeocodingNotFoundError,
    UpstreamIntegrationError,
)
from .company_lookup_service import CompanyLookupService
from .crm_service import CrmService
from .geocoding_service import GeocodingService
from .postgrest_client import PostgrestClient

# Filho de "uvicorn.error" pra aparecer nos logs do container sem configurar o
# logging raiz (que ligaria o INFO do httpx, cujas URLs incluem chaves de API).
logger = logging.getLogger("uvicorn.error.crm_sync")

STATE_KEY = "companies"
MAX_ATTEMPTS = 5
PENDING_BATCH = 25
BACKOFF_BASE_MINUTES = 10
BACKOFF_MAX_MINUTES = 360


def _only_digits(value: str | None) -> str:
    return re.sub(r"\D", "", value or "")


def _parse_date(raw: str | None) -> str | None:
    # data_abertura chega como yyyymmdd (shape legado do CompanyLookupService).
    if not raw or raw == "00000000" or len(raw) < 8:
        return None
    return f"{raw[0:4]}-{raw[4:6]}-{raw[6:8]}"


def build_geocoding_address(data: dict) -> str:
    # Mesmo formato do cadastro manual (add_company_modal.dart).
    return (
        f"{data.get('log_tipo') or ''} {data.get('log_nome') or ''}, "
        f"{data.get('log_num') or ''} - {data.get('log_bairro') or ''}, "
        f"{data.get('log_municipio') or ''} - {data.get('log_uf') or ''}"
    )


def build_company_row(data: dict, cnpj: str, lat: float, lon: float, precisao: str):
    """Linha de `companies` a partir do shape do CompanyLookupService — o MESMO
    mapeamento de RegistrationService.saveCompany (registration_service.dart),
    pra empresa vinda do CRM ficar idêntica à cadastrada pelo app."""
    ddd = data.get("ddd_1") or ""
    tel = data.get("tel_1") or ""
    return {
        "cnpj": cnpj,
        "razao_social": data.get("razao"),
        # a BrasilAPI manda string vazia quando não há fantasia: NULL, senão o app
        # (que só cai pra razão social em NULL) mostra o título em branco
        "nome_fantasia": (data.get("fantasia") or "").strip() or None,
        "email_principal": data.get("email"),
        "url_company_page": data.get("site"),
        "telefone_principal": f"{ddd}{tel}" if ddd and tel else None,
        "endereco_completo": (
            f"{data.get('log_tipo') or ''} {data.get('log_nome') or ''}, "
            f"{data.get('log_num') or ''} - {data.get('log_bairro') or ''}"
        ),
        "tipo_logradouro": data.get("log_tipo"),
        "logradouro": data.get("log_nome"),
        "numero": data.get("log_num"),
        "bairro": data.get("log_bairro"),
        "municipio": data.get("log_municipio"),
        "uf": data.get("log_uf"),
        "cep": data.get("log_cep"),
        "natureza_juridica": data.get("natureza_juridica"),
        "porte": data.get("porte"),
        "situacao": data.get("situacao_cadastral"),
        "data_abertura": _parse_date(data.get("data_abertura")),
        "cnae_principal": data.get("cnae_principal"),
        "latitude": lat,
        "longitude": lon,
        "precisao_geocodificacao": precisao,
    }


@dataclass
class Candidate:
    crm_id: str
    cnpj: str
    attempts: int = 0  # tentativas anteriores (só > 0 vindo de crm_sync_pending)
    from_pending: bool = False


@dataclass
class CycleResult:
    initialized: bool = False
    fetched: int = 0
    imported: int = 0
    linked: int = 0
    unchanged: int = 0
    failed: int = 0
    skipped: int = 0


class CrmSyncService:
    """Traz pro banco as empresas criadas no CRM (mini ETL), a cada ciclo.

    O custo de um ciclo sem novidade é: 1 consulta à marca d'água, 1 chamada
    ao Search do HubSpot (já filtrada por ID > marca d'água) e 1 consulta à
    fila de pendências (tabela minúscula). Nunca lista o CRM nem varre
    `companies`: o único acesso a `companies` é a deduplicação por CNPJ do
    lote devolvido pelo CRM (no máximo `crm_sync_batch_size` CNPJs, com índice).
    """

    def __init__(
        self,
        crm: CrmService,
        lookup: CompanyLookupService,
        geocoder: GeocodingService,
        db: PostgrestClient,
        *,
        clock: Callable[[], float] = time.time,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._crm = crm
        self._lookup = lookup
        self._geocoder = geocoder
        self._db = db
        self._clock = clock
        self._sleep = sleep

    async def run_forever(self) -> None:
        interval = settings.crm_sync_interval_seconds
        while True:
            try:
                result = await self.run_cycle()
                logger.info("Sincronização com o CRM: %s", result)
            except Exception:
                # Um ciclo ruim (CRM fora do ar, banco reiniciando) não pode
                # derrubar o job nem o app: o próximo ciclo tenta de novo.
                logger.exception("Falha no ciclo de sincronização com o CRM")
            await self._sleep(interval)

    async def run_cycle(self) -> CycleResult:
        result = CycleResult()

        state = await self._get_state()
        if state is None:
            # Primeira execução sem backfill: parte do estado atual do CRM,
            # em vez de importar a base inteira sem querer.
            latest = await self._crm.latest_company_id()
            await self._save_state(latest, "initialized")
            result.initialized = True
            return result
        last_id = int(state["last_crm_id"])

        since_ms = int(
            (self._clock() - settings.crm_sync_overlap_minutes * 60) * 1000
        )
        rows = await self._crm.find_new_companies(
            last_id, since_ms, settings.crm_sync_batch_size
        )
        result.fetched = len(rows)

        candidates = self._candidates_from_crm(rows, result)

        # Empresa reaparecida pela janela de sobreposição que já está na fila
        # de pendências só é retentada quando o backoff vence (via
        # _due_pending), não a cada ciclo.
        reseen = [crm_id for crm_id in candidates if int(crm_id) <= last_id]
        if reseen:
            for crm_id in await self._pending_ids(reseen):
                candidates.pop(crm_id, None)

        for pending in await self._due_pending():
            candidates[pending.crm_id] = pending  # retentativa substitui o novo

        if candidates:
            await self._process(list(candidates.values()), result)

        if rows:
            new_last = max(int(row["id"]) for row in rows)
            if new_last > last_id:
                await self._save_state(new_last, self._status(result))
        return result

    async def backfill(
        self, *, company_pause: float = 0.2, page_pause: float = 1.0
    ) -> CycleResult:
        """Importação única do histórico do CRM, paginada por ID (reiniciando
        o filtro a partir do último ID, pra não esbarrar no limite de 10.000
        resultados do Search). Idempotente: pode ser reexecutada."""
        total = CycleResult()
        cursor = 0
        while True:
            rows = await self._crm.find_new_companies(
                cursor, None, settings.crm_sync_batch_size
            )
            if not rows:
                break
            page = CycleResult(fetched=len(rows))
            candidates = self._candidates_from_crm(rows, page)
            if candidates:
                await self._process(
                    list(candidates.values()), page, pause=company_pause
                )
            cursor = max(int(row["id"]) for row in rows)
            for field in ("fetched", "imported", "linked", "unchanged",
                          "failed", "skipped"):
                setattr(total, field, getattr(total, field) + getattr(page, field))
            logger.info("Backfill até o ID %s: %s", cursor, page)
            await self._sleep(page_pause)

        if cursor:
            state = await self._get_state()
            current = int(state["last_crm_id"]) if state else 0
            await self._save_state(max(current, cursor), "backfill")
        return total

    # ─── ETL ────────────────────────────────────────────────────────────

    def _candidates_from_crm(
        self, rows: list[dict], result: CycleResult
    ) -> dict[str, Candidate]:
        candidates: dict[str, Candidate] = {}
        for row in rows:
            raw = (row.get("properties") or {}).get(settings.crm_cnpj_property_name)
            cnpj = _only_digits(raw)
            if len(cnpj) != 14:
                logger.warning(
                    "Empresa %s do CRM ignorada: CNPJ inválido (%r)", row["id"], raw
                )
                result.skipped += 1
                continue
            candidates[str(row["id"])] = Candidate(crm_id=str(row["id"]), cnpj=cnpj)
        return candidates

    async def _process(
        self, candidates: list[Candidate], result: CycleResult, *, pause: float = 0
    ) -> None:
        existing = await self._existing_by_cnpj({c.cnpj for c in candidates})

        for candidate in candidates:
            company = existing.get(candidate.cnpj)
            try:
                if company is not None:
                    await self._link_existing(candidate, company, result)
                else:
                    await self._import_new(candidate, result)
            except (
                CnpjNotFoundError,
                GeocodingNotFoundError,
                UpstreamIntegrationError,
            ) as exc:
                await self._mark_failed(candidate, exc)
                result.failed += 1
            if pause:
                await self._sleep(pause)

    async def _existing_by_cnpj(self, cnpjs: set[str]) -> dict[str, dict]:
        # Um único SELECT indexado (cnpj é UNIQUE) restrito ao lote do CRM,
        # já trazendo o vínculo atual com o CRM.
        rows = await self._db.select(
            "companies",
            {
                "cnpj": f"in.({','.join(sorted(cnpjs))})",
                "select": "id,cnpj,company_crm_sync(crm_object_id)",
            },
        )
        return {row["cnpj"]: row for row in rows}

    async def _link_existing(
        self, candidate: Candidate, company: dict, result: CycleResult
    ) -> None:
        link = company.get("company_crm_sync")
        if isinstance(link, list):
            link = link[0] if link else None

        if link and link.get("crm_object_id") == candidate.crm_id:
            result.unchanged += 1  # reconsulta da janela de sobreposição
        else:
            await self._write_link(company["id"], candidate.crm_id)
            result.linked += 1
        await self._clear_pending(candidate)

    async def _import_new(self, candidate: Candidate, result: CycleResult) -> None:
        data = await self._lookup.lookup_cnpj(candidate.cnpj)
        geo = await self._geocoder.geocode(build_geocoding_address(data))
        row = build_company_row(
            data, candidate.cnpj, geo.latitude, geo.longitude, geo.precisao
        )
        # DO NOTHING: se o app cadastrou a mesma empresa no meio do caminho,
        # o cadastro dele prevalece.
        await self._db.insert(
            "companies", [row], on_conflict="cnpj", ignore_duplicates=True
        )
        created = await self._db.select(
            "companies", {"cnpj": f"eq.{candidate.cnpj}", "select": "id"}
        )
        await self._write_link(created[0]["id"], candidate.crm_id)
        await self._clear_pending(candidate)
        result.imported += 1

    async def _write_link(self, company_id: str, crm_id: str) -> None:
        await self._db.upsert(
            "company_crm_sync",
            [
                {
                    "company_id": company_id,
                    "crm_object_id": crm_id,
                    "last_synced_at": self._now_iso(),
                    "sync_status": "synced",
                }
            ],
            on_conflict="company_id",
        )

    # ─── Estado e pendências ────────────────────────────────────────────

    async def _get_state(self) -> dict | None:
        rows = await self._db.select(
            "crm_sync_state", {"key": f"eq.{STATE_KEY}", "select": "*"}
        )
        return rows[0] if rows else None

    async def _save_state(self, last_crm_id: int, status: str) -> None:
        await self._db.upsert(
            "crm_sync_state",
            [
                {
                    "key": STATE_KEY,
                    "last_crm_id": last_crm_id,
                    "last_run_at": self._now_iso(),
                    "last_status": status,
                }
            ],
            on_conflict="key",
        )

    async def _pending_ids(self, crm_ids: list[str]) -> set[str]:
        rows = await self._db.select(
            "crm_sync_pending",
            {
                "crm_object_id": f"in.({','.join(crm_ids)})",
                "select": "crm_object_id",
            },
        )
        return {row["crm_object_id"] for row in rows}

    async def _due_pending(self) -> list[Candidate]:
        rows = await self._db.select(
            "crm_sync_pending",
            {
                "next_retry_at": f"lte.{self._now_iso()}",
                "attempts": f"lt.{MAX_ATTEMPTS}",
                "order": "next_retry_at.asc",
                "limit": str(PENDING_BATCH),
                "select": "crm_object_id,cnpj,attempts",
            },
        )
        return [
            Candidate(
                crm_id=row["crm_object_id"],
                cnpj=row["cnpj"],
                attempts=row["attempts"],
                from_pending=True,
            )
            for row in rows
        ]

    async def _mark_failed(self, candidate: Candidate, exc: Exception) -> None:
        attempts = candidate.attempts + 1
        backoff = min(BACKOFF_BASE_MINUTES * 2**attempts, BACKOFF_MAX_MINUTES)
        logger.warning(
            "Empresa %s (CNPJ %s) falhou, tentativa %s: %s",
            candidate.crm_id,
            candidate.cnpj,
            attempts,
            exc,
        )
        await self._db.upsert(
            "crm_sync_pending",
            [
                {
                    "crm_object_id": candidate.crm_id,
                    "cnpj": candidate.cnpj,
                    "attempts": attempts,
                    "last_error": str(exc)[:500],
                    "next_retry_at": self._iso(self._clock() + backoff * 60),
                }
            ],
            on_conflict="crm_object_id",
        )

    async def _clear_pending(self, candidate: Candidate) -> None:
        if candidate.from_pending:
            await self._db.delete(
                "crm_sync_pending", {"crm_object_id": f"eq.{candidate.crm_id}"}
            )

    # ─── Utilidades ─────────────────────────────────────────────────────

    @staticmethod
    def _status(result: CycleResult) -> str:
        return "ok" if result.failed == 0 else f"ok_com_{result.failed}_falhas"

    @staticmethod
    def _iso(epoch_seconds: float) -> str:
        return datetime.fromtimestamp(epoch_seconds, tz=timezone.utc).isoformat()

    def _now_iso(self) -> str:
        return self._iso(self._clock())
