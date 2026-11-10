import time

import httpx

from ..config import settings
from ..errors import UpstreamIntegrationError
from ..internal_token import mint_internal_token

SYNC_UID = "crm-sync"
SYNC_ROLE = "crm_sync"


class PostgrestClient:
    """Acesso do Backend ao banco, pelo PostgREST (o Backend não tem driver de
    Postgres). Usa um token interno com role `crm_sync` — privilégio mínimo,
    definido em db/schema/008_crm_sync.sql — e renova o token quando falta
    pouco pra expirar."""

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(
            base_url=settings.postgrest_url, timeout=15.0
        )
        self._token: str | None = None
        self._expires_at = 0

    async def aclose(self) -> None:
        await self._client.aclose()

    def _auth_headers(self) -> dict[str, str]:
        if self._token is None or time.time() >= self._expires_at - 60:
            minted = mint_internal_token(SYNC_UID, role=SYNC_ROLE)
            self._token = minted["token"]
            self._expires_at = minted["expires_at"]
        return {"Authorization": f"Bearer {self._token}"}

    async def select(self, table: str, params: dict[str, str]) -> list[dict]:
        return await self._request("GET", f"/{table}", params=params) or []

    async def insert(
        self,
        table: str,
        rows: list[dict],
        *,
        on_conflict: str | None = None,
        ignore_duplicates: bool = False,
    ) -> None:
        prefer = ["return=minimal"]
        if ignore_duplicates:
            prefer.append("resolution=ignore-duplicates")
        params = {"on_conflict": on_conflict} if on_conflict else None
        await self._request(
            "POST",
            f"/{table}",
            params=params,
            json=rows,
            headers={"Prefer": ",".join(prefer)},
        )

    async def upsert(self, table: str, rows: list[dict], on_conflict: str) -> None:
        await self._request(
            "POST",
            f"/{table}",
            params={"on_conflict": on_conflict},
            json=rows,
            headers={"Prefer": "resolution=merge-duplicates,return=minimal"},
        )

    async def update(
        self, table: str, params: dict[str, str], values: dict
    ) -> None:
        """PATCH nas linhas que casam com `params`. Existe porque um upsert
        parcial não serve: o INSERT do ON CONFLICT valida as colunas NOT NULL
        antes de detectar o conflito."""
        await self._request(
            "PATCH",
            f"/{table}",
            params=params,
            json=values,
            headers={"Prefer": "return=minimal"},
        )

    async def delete(self, table: str, params: dict[str, str]) -> None:
        await self._request("DELETE", f"/{table}", params=params)

    async def _request(self, method: str, path: str, **kwargs):
        headers = {**self._auth_headers(), **kwargs.pop("headers", {})}
        try:
            response = await self._client.request(
                method, path, headers=headers, **kwargs
            )
        except httpx.RequestError as exc:
            raise UpstreamIntegrationError(
                f"Falha de rede ao chamar o banco ({method} {path}): {exc}"
            ) from exc

        if response.status_code >= 400:
            raise UpstreamIntegrationError(
                f"Banco respondeu {response.status_code} em {method} {path}: "
                f"{response.text}"
            )
        return response.json() if response.content else None
