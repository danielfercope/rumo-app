from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, HTTPException

from .errors import (
    CnpjNotFoundError,
    CrmCompanyNotFoundError,
    UnauthenticatedError,
    UpstreamIntegrationError,
)
from .schemas import CompanyLookupRequest, CrmRequest
from .services.auth_service import AuthService
from .services.company_lookup_service import CompanyLookupService
from .services.crm_service import CrmService

auth_service = AuthService()
company_lookup_service = CompanyLookupService()
crm_service = CrmService()


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    await company_lookup_service.aclose()
    await crm_service.aclose()


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
