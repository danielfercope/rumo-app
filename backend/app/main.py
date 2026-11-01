import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException

from .errors import (
    CnpjNotFoundError,
    CrmCompanyNotFoundError,
    UnauthenticatedError,
    UpstreamIntegrationError,
)
from .config import settings
from .schemas import CompanyLookupRequest, CrmRequest
from .services.auth_service import AuthService
from .services.company_lookup_service import CompanyLookupService
from .services.crm_service import CrmService
from .services.crm_sync_service import CrmSyncService
from .services.geocoding_service import GeocodingService
from .services.postgrest_client import PostgrestClient

logger = logging.getLogger("uvicorn.error.crm_sync")

auth_service = AuthService()
company_lookup_service = CompanyLookupService()
crm_service = CrmService()
geocoding_service = GeocodingService()
postgrest_client = PostgrestClient()
crm_sync_service = CrmSyncService(
    crm_service, company_lookup_service, geocoding_service, postgrest_client
)


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
    yield
    if sync_task is not None:
        sync_task.cancel()
        await asyncio.gather(sync_task, return_exceptions=True)
    await company_lookup_service.aclose()
    await crm_service.aclose()
    await geocoding_service.aclose()
    await postgrest_client.aclose()


app = FastAPI(title="rumo-backend", lifespan=lifespan)


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
