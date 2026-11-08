"""Escrita do seed numa conta de teste do HubSpot.

Cada empresa criada carrega `rumo_seed_lote=<lote>`: é o que permite achar (e
apagar) exatamente o que o seed criou, sem tocar no resto da conta.

Só vão propriedades de identificação da EMPRESA (nome, CNPJ, cidade, UF, estágio
do ciclo de vida). Nunca telefone, e-mail ou contatos: o HubSpot não passa a ter
como contatar essas empresas. Precisa de um token com escopo de ESCRITA em
empresas e em esquemas de empresas — diferente do token só-leitura do app."""

import asyncio
import re
from collections.abc import Awaitable, Callable, Sequence

import httpx

from .labeling import Labeled

BASE_URL = "https://api.hubapi.com"
BATCH = 100  # limite do HubSpot por chamada em lote

LIFECYCLE = {"cliente": "customer", "lead": "lead", "perdido": "other"}

CUSTOM_PROPERTIES = (
    ("cnpj", "CNPJ"),
    ("rumo_seed_lote", "Lote do seed (RUMO)"),
)


class HubSpotError(Exception):
    pass


def company_properties(item: Labeled, status: str, lote: str) -> dict[str, str]:
    c = item.company
    return {
        "name": c.nome_fantasia or c.razao_social,
        "cnpj": re.sub(r"\D", "", c.cnpj),
        "city": c.municipio,
        "state": c.uf,
        "lifecyclestage": LIFECYCLE[status],
        "rumo_seed_lote": lote,
    }


def _chunks(seq: Sequence, size: int):
    for i in range(0, len(seq), size):
        yield seq[i : i + size]


class HubSpotSeeder:
    def __init__(
        self,
        token: str,
        *,
        client: httpx.AsyncClient | None = None,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        pause: float = 0.3,
    ) -> None:
        self._client = client or httpx.AsyncClient(
            base_url=BASE_URL,
            timeout=30.0,
            headers={"Authorization": f"Bearer {token}"},
        )
        self._owns = client is None
        self._sleep = sleep
        self._pause = pause

    async def aclose(self) -> None:
        if self._owns:
            await self._client.aclose()

    async def _request(self, method: str, path: str, **kwargs) -> dict:
        for attempt in range(6):
            response = await self._client.request(method, path, **kwargs)
            if response.status_code == 429:
                wait = float(response.headers.get("Retry-After", 2 * 2**attempt))
                await self._sleep(min(wait, 30.0))
                continue
            if response.status_code in (401, 403):
                raise HubSpotError(
                    "O HubSpot recusou o token (inválido ou sem escopo de escrita "
                    "em empresas)."
                )
            if response.status_code >= 400:
                # o corpo do HubSpot descreve o erro e não inclui o token
                raise HubSpotError(
                    f"HubSpot respondeu {response.status_code} em {method} {path}: "
                    f"{response.text[:300]}"
                )
            await self._sleep(self._pause)
            return response.json() if response.content else {}
        raise HubSpotError(f"HubSpot limitou as requisições em {method} {path}")

    # ─── Esquema ────────────────────────────────────────────────────────

    async def ensure_properties(self) -> list[str]:
        """Cria as propriedades personalizadas que faltam. Devolve as criadas."""
        created = []
        for name, label in CUSTOM_PROPERTIES:
            response = await self._client.get(f"/crm/v3/properties/companies/{name}")
            if response.status_code == 200:
                continue
            if response.status_code != 404:
                raise HubSpotError(
                    f"HubSpot respondeu {response.status_code} ao ler a propriedade {name}"
                )
            await self._request(
                "POST",
                "/crm/v3/properties/companies",
                json={
                    "name": name,
                    "label": label,
                    "type": "string",
                    "fieldType": "text",
                    "groupName": "companyinformation",
                },
            )
            created.append(name)
        return created

    # ─── Leitura do lote ────────────────────────────────────────────────

    async def existing(self, lote: str) -> dict[str, dict]:
        """cnpj → {id, lifecyclestage} das empresas já criadas neste lote."""
        found: dict[str, dict] = {}
        after: str | None = None
        while True:
            body: dict = {
                "filterGroups": [
                    {
                        "filters": [
                            {
                                "propertyName": "rumo_seed_lote",
                                "operator": "EQ",
                                "value": lote,
                            }
                        ]
                    }
                ],
                "properties": ["cnpj", "lifecyclestage"],
                "limit": BATCH,
            }
            if after:
                body["after"] = after
            data = await self._request(
                "POST", "/crm/v3/objects/companies/search", json=body
            )
            for row in data.get("results") or []:
                props = row.get("properties") or {}
                if props.get("cnpj"):
                    found[props["cnpj"]] = {
                        "id": row["id"],
                        "lifecyclestage": props.get("lifecyclestage"),
                    }
            after = ((data.get("paging") or {}).get("next") or {}).get("after")
            if not after:
                return found

    # ─── Escrita ────────────────────────────────────────────────────────

    async def create(self, payloads: list[dict[str, str]], lote: str) -> int:
        """Cria as empresas que ainda não existem no lote. Devolve quantas criou."""
        already = await self.existing(lote)
        todo = [p for p in payloads if p["cnpj"] not in already]
        for chunk in _chunks(todo, BATCH):
            await self._request(
                "POST",
                "/crm/v3/objects/companies/batch/create",
                json={"inputs": [{"properties": p} for p in chunk]},
            )
        return len(todo)

    async def set_status(self, lote: str, targets: dict[str, str]) -> int:
        """Muda o ciclo de vida de quem já existe no lote (cnpj → status)."""
        found = await self.existing(lote)
        updates = [
            {"id": found[cnpj]["id"], "properties": {"lifecyclestage": LIFECYCLE[status]}}
            for cnpj, status in targets.items()
            if cnpj in found
            and found[cnpj]["lifecyclestage"] != LIFECYCLE[status]
        ]
        for chunk in _chunks(updates, BATCH):
            await self._request(
                "POST",
                "/crm/v3/objects/companies/batch/update",
                json={"inputs": chunk},
            )
        return len(updates)

    async def delete_lote(self, lote: str) -> int:
        found = await self.existing(lote)
        ids = [v["id"] for v in found.values()]
        for chunk in _chunks(ids, BATCH):
            await self._request(
                "POST",
                "/crm/v3/objects/companies/batch/archive",
                json={"inputs": [{"id": i} for i in chunk]},
            )
        return len(ids)
