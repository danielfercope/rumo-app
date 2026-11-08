import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, Header, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from .errors import (
    CnpjNotFoundError,
    ConnectionNotFoundError,
    CrmCompanyNotFoundError,
    InvalidCrmTokenError,
    InvalidMappingError,
    NotGroupAdminError,
    SyncInProgressError,
    TokenCipherError,
    UnauthenticatedError,
    UpstreamIntegrationError,
)
from .config import settings
from .schemas import (
    CompanyLookupRequest,
    ConectarCrmRequest,
    CredencialCrm,
    CrmRequest,
    PreviaCarteiraRequest,
)
from .services.auth_service import AuthService
from .services.company_lookup_service import CompanyLookupService
from .services.carteira_connection_service import CarteiraConnectionService
from .services.carteira_sync_service import CarteiraSyncService
from .services.crm_service import CrmService
from .services.crm_sync_service import CrmSyncService
from .services.geocoding_service import GeocodingService
from .services.postgrest_client import PostgrestClient
from .services.token_cipher import TokenCipher

logger = logging.getLogger("uvicorn.error.crm_sync")

auth_service = AuthService()
company_lookup_service = CompanyLookupService()
crm_service = CrmService()
geocoding_service = GeocodingService()
postgrest_client = PostgrestClient()
crm_sync_service = CrmSyncService(
    crm_service, company_lookup_service, geocoding_service, postgrest_client
)


def _build_carteira_services() -> tuple[CarteiraSyncService, CarteiraConnectionService] | None:
    """Sync e casos de uso da conexão por organização. Sem chave de cifra não
    dá pra guardar nem ler token de CRM: devolve None e os endpoints /carteira
    respondem 503, em vez de derrubar o Backend inteiro."""
    try:
        cipher = TokenCipher()
    except TokenCipherError as exc:
        logger.warning("Conexão de CRM por organização indisponível: %s", exc)
        return None
    sync = CarteiraSyncService(
        postgrest_client, company_lookup_service, geocoding_service, cipher
    )
    return sync, CarteiraConnectionService(postgrest_client, cipher, sync)


_carteira = _build_carteira_services()
carteira_sync_service = _carteira[0] if _carteira else None
carteira_connection_service = _carteira[1] if _carteira else None


@asynccontextmanager
async def lifespan(app: FastAPI):
    sync_task: asyncio.Task | None = None
    if settings.crm_sync_enabled:
        if settings.crm_token and settings.geocoding_api_key:
            sync_task = asyncio.create_task(crm_sync_service.run_forever())
        else:
            logger.error(
                "CRM_SYNC_ENABLED=true, mas CRM_TOKEN e/ou GEOCODING_API_KEY "
                "estão vazios — sincronização com o CRM não iniciada."
            )

    carteira_task: asyncio.Task | None = None
    if settings.crm_connections_sync_enabled:
        if carteira_sync_service is not None and settings.geocoding_api_key:
            carteira_task = asyncio.create_task(carteira_sync_service.run_forever())
        else:
            logger.error(
                "CRM_CONNECTIONS_SYNC_ENABLED=true, mas CRM_TOKEN_ENCRYPTION_KEY "
                "e/ou GEOCODING_API_KEY estão vazios — sincronização das "
                "carteiras não iniciada."
            )
    yield
    for task in (sync_task, carteira_task):
        if task is not None:
            task.cancel()
    await asyncio.gather(
        *(t for t in (sync_task, carteira_task) if t is not None),
        return_exceptions=True,
    )
    await company_lookup_service.aclose()
    await crm_service.aclose()
    await geocoding_service.aclose()
    await postgrest_client.aclose()


app = FastAPI(title="rumo-backend", lifespan=lifespan)


@app.exception_handler(RequestValidationError)
async def validation_error_handler(
    request: Request, exc: RequestValidationError
) -> JSONResponse:
    # O 422 padrão devolve `input`, que num campo ausente é o corpo INTEIRO —
    # e o corpo de /carteira/* carrega o token de CRM da organização. Devolve
    # só onde e o quê, nunca o valor enviado.
    detail = [
        {"loc": list(e["loc"]), "msg": e["msg"], "type": e["type"]}
        for e in exc.errors()
    ]
    return JSONResponse(status_code=422, content={"detail": detail})


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/auth/exchange")
def exchange_token(authorization: str = Header(...)) -> dict:
    try:
        return auth_service.exchange_token(authorization)
    except UnauthenticatedError as exc:
        raise HTTPException(401, str(exc)) from exc


@app.post("/company-lookup")
async def company_lookup(payload: CompanyLookupRequest) -> dict:
    try:
        return await company_lookup_service.lookup_cnpj(payload.cnpj)
    except CnpjNotFoundError as exc:
        raise HTTPException(404, str(exc)) from exc
    except UpstreamIntegrationError as exc:
        raise HTTPException(502, str(exc)) from exc


@app.post("/crm")
async def crm(payload: CrmRequest) -> dict:
    try:
        return await crm_service.handle(payload)
    except CrmCompanyNotFoundError as exc:
        raise HTTPException(404, str(exc)) from exc
    except UpstreamIntegrationError as exc:
        raise HTTPException(502, str(exc)) from exc


# ─── Conexão da organização com o CRM (carteira) ────────────────────────
# Identidade = o token interno que o app já usa; só admin da organização.


def current_uid(authorization: str = Header(...)) -> str:
    try:
        return auth_service.uid_from_internal_token(authorization)
    except UnauthenticatedError as exc:
        raise HTTPException(401, str(exc)) from exc


def _connection_service() -> CarteiraConnectionService:
    if carteira_connection_service is None:
        raise HTTPException(
            503, "Conexão com o CRM indisponível: chave de cifra não configurada."
        )
    return carteira_connection_service


async def _carteira_call(coro):
    try:
        return await coro
    except NotGroupAdminError as exc:
        raise HTTPException(403, str(exc)) from exc
    except ConnectionNotFoundError as exc:
        raise HTTPException(404, str(exc)) from exc
    except SyncInProgressError as exc:
        raise HTTPException(409, str(exc)) from exc
    except (InvalidCrmTokenError, InvalidMappingError) as exc:
        raise HTTPException(400, str(exc)) from exc
    except UpstreamIntegrationError as exc:
        raise HTTPException(502, str(exc)) from exc


@app.post("/carteira/conexao/validar")
async def validar_conexao(
    payload: CredencialCrm, uid: str = Depends(current_uid)
) -> dict:
    props = await _carteira_call(
        _connection_service().validate(
            uid, payload.group_id, payload.provedor, payload.token
        )
    )
    return {
        "propriedades": [
            {"name": p.name, "label": p.label, "type": p.type} for p in props
        ]
    }


@app.post("/carteira/conexao/previa")
async def previa_conexao(
    payload: PreviaCarteiraRequest, uid: str = Depends(current_uid)
) -> dict:
    return await _carteira_call(
        _connection_service().preview(
            uid,
            payload.group_id,
            payload.provedor,
            payload.token,
            payload.mapeamento.model_dump(),
        )
    )


@app.put("/carteira/conexao", status_code=202)
async def conectar_crm(
    payload: ConectarCrmRequest, uid: str = Depends(current_uid)
) -> dict:
    return await _carteira_call(
        _connection_service().connect(
            uid,
            payload.group_id,
            payload.provedor,
            payload.token,
            payload.mapeamento.model_dump(),
        )
    )


@app.post("/carteira/conexao/sincronizar", status_code=202)
async def sincronizar_agora(group_id: str, uid: str = Depends(current_uid)) -> dict:
    return await _carteira_call(_connection_service().sync_now(uid, group_id))


@app.delete("/carteira/conexao", status_code=204)
async def desconectar_crm(
    group_id: str, apagar_carteira: bool = False, uid: str = Depends(current_uid)
) -> None:
    await _carteira_call(
        _connection_service().disconnect(uid, group_id, apagar_carteira)
    )
