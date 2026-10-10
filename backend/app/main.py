from fastapi import FastAPI, Header, HTTPException

from .errors import NotImplementedIntegrationError, UnauthenticatedError
from .services.auth_service import AuthService
from .services.empresa_aqui_service import EmpresaAquiService
from .services.hubspot_service import HubSpotService

app = FastAPI(title="rumo-backend")

auth_service = AuthService()
empresa_aqui_service = EmpresaAquiService()
hubspot_service = HubSpotService()


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/auth/exchange")
def exchange_token(authorization: str = Header(...)) -> dict:
    try:
        return auth_service.exchange_token(authorization)
    except UnauthenticatedError as exc:
        raise HTTPException(401, str(exc)) from exc


@app.post("/empresa-aqui")
async def empresa_aqui(payload: dict) -> dict:
    try:
        return await empresa_aqui_service.lookup_cnpj(payload)
    except NotImplementedIntegrationError as exc:
        raise HTTPException(501, str(exc)) from exc


@app.post("/hubspot")
async def hubspot(payload: dict) -> dict:
    try:
        return await hubspot_service.handle(payload)
    except NotImplementedIntegrationError as exc:
        raise HTTPException(501, str(exc)) from exc
