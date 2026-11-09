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

from . import relacionados
from .labeling import Labeled

BASE_URL = "https://api.hubapi.com"
BATCH = 100  # limite do HubSpot por chamada em lote

LIFECYCLE = {"cliente": "customer", "lead": "lead", "perdido": "other"}

CUSTOM_PROPERTIES = (
    ("cnpj", "CNPJ"),
    ("rumo_seed_lote", "Lote do seed (RUMO)"),
)


# tipos de associação padrão do HubSpot (HUBSPOT_DEFINED)
CONTACT_TO_COMPANY = 1
DEAL_TO_COMPANY = 5
DEAL_TO_CONTACT = 3


def _link(to_id: str, type_id: int) -> dict:
    return {
        "to": {"id": to_id},
        "types": [{"associationCategory": "HUBSPOT_DEFINED", "associationTypeId": type_id}],
    }


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

    # ─── Contatos e negócios fictícios ──────────────────────────────────

    async def _associated(self, from_type: str, to_type: str, ids: list[str]) -> dict[str, list[str]]:
        """id da origem → ids associados (leitura em lote, v4)."""
        found: dict[str, list[str]] = {}
        for chunk in _chunks(ids, BATCH):
            data = await self._request(
                "POST",
                f"/crm/v4/associations/{from_type}/{to_type}/batch/read",
                json={"inputs": [{"id": i} for i in chunk]},
            )
            for row in data.get("results") or []:
                found[row["from"]["id"]] = [str(t["toObjectId"]) for t in row.get("to") or []]
        return found

    async def _read_objects(self, object_type: str, ids: list[str], properties: list[str]) -> dict[str, dict]:
        rows: dict[str, dict] = {}
        for chunk in _chunks(ids, BATCH):
            data = await self._request(
                "POST",
                f"/crm/v3/objects/{object_type}/batch/read",
                json={"properties": properties, "inputs": [{"id": i} for i in chunk]},
            )
            for row in data.get("results") or []:
                rows[row["id"]] = row.get("properties") or {}
        return rows

    async def related(self, lote: str, company_ids: list[str]) -> dict[str, dict[str, list[str]]]:
        """company_id → {"contacts": [...], "deals": [...]} só do que é do lote."""
        out = {i: {"contacts": [], "deals": []} for i in company_ids}
        contact_links = await self._associated("companies", "contacts", company_ids)
        deal_links = await self._associated("companies", "deals", company_ids)
        contacts = await self._read_objects(
            "contacts", sorted({c for v in contact_links.values() for c in v}), ["email"]
        )
        deals = await self._read_objects(
            "deals", sorted({d for v in deal_links.values() for d in v}), ["dealname"]
        )
        for company_id in company_ids:
            out[company_id]["contacts"] = [
                c for c in contact_links.get(company_id, [])
                if relacionados.is_seed_contact(contacts.get(c, {}))
            ]
            out[company_id]["deals"] = [
                d for d in deal_links.get(company_id, [])
                if relacionados.is_seed_deal(deals.get(d, {}), lote)
            ]
        return out

    async def create_related(self, lote: str, items: list[tuple[str, dict, dict]]) -> tuple[int, int]:
        """items: (company_id, propriedades do contato, propriedades do negócio).

        Cria o que falta e associa contato↔empresa, negócio↔empresa e
        negócio↔contato. Quem já tem contato/negócio do lote é preservado.
        Devolve (contatos criados, negócios criados)."""
        have = await self.related(lote, [i[0] for i in items])
        new_contacts = [it for it in items if not have[it[0]]["contacts"]]

        contact_id: dict[str, str] = {c: ids["contacts"][0] for c, ids in have.items() if ids["contacts"]}
        for chunk in _chunks(new_contacts, BATCH):
            data = await self._request(
                "POST",
                "/crm/v3/objects/contacts/batch/create",
                json={"inputs": [
                    {"properties": c, "associations": [_link(cid, CONTACT_TO_COMPANY)]}
                    for cid, c, _ in chunk
                ]},
            )
            by_email = {
                (r.get("properties") or {}).get("email", "").lower(): r["id"]
                for r in data.get("results") or []
            }
            for cid, props, _ in chunk:
                contact_id[cid] = by_email[props["email"].lower()]

        new_deals = [it for it in items if not have[it[0]]["deals"]]
        for chunk in _chunks(new_deals, BATCH):
            await self._request(
                "POST",
                "/crm/v3/objects/deals/batch/create",
                json={"inputs": [
                    {
                        "properties": d,
                        "associations": [
                            _link(cid, DEAL_TO_COMPANY),
                            _link(contact_id[cid], DEAL_TO_CONTACT),
                        ],
                    }
                    for cid, _, d in chunk
                ]},
            )
        return len(new_contacts), len(new_deals)

    async def delete_related(self, lote: str) -> tuple[int, int]:
        """Arquiva contatos e negócios do lote. Rode ANTES de apagar as empresas:
        é a associação com a empresa que os encontra."""
        companies = await self.existing(lote)
        found = await self.related(lote, [v["id"] for v in companies.values()])
        contacts = sorted({c for v in found.values() for c in v["contacts"]})
        deals = sorted({d for v in found.values() for d in v["deals"]})
        for object_type, ids in (("deals", deals), ("contacts", contacts)):
            for chunk in _chunks(ids, BATCH):
                await self._request(
                    "POST",
                    f"/crm/v3/objects/{object_type}/batch/archive",
                    json={"inputs": [{"id": i} for i in chunk]},
                )
        return len(contacts), len(deals)
