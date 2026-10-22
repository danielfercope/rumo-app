import time
from datetime import datetime, timezone

import httpx

from ..config import settings
from ..errors import CrmCompanyNotFoundError, UpstreamIntegrationError
from ..schemas import CrmRequest

BASE_URL = "https://api.hubapi.com"


def _normalize_timestamp(value: str | int) -> str:
    # hs_timestamp é enviado como epoch ms na criação, mas o HubSpot devolve
    # ISO-8601 na leitura (confirmado contra a API real) — aceita os dois.
    try:
        epoch_ms = int(value)
    except (TypeError, ValueError):
        return str(value)
    dt = datetime.fromtimestamp(epoch_ms / 1000, tz=timezone.utc)
    return dt.isoformat().replace("+00:00", "Z")


class CrmService:
    """Integração com o CRM (hoje HubSpot, API v3/v4). Nome agnóstico de
    propósito: se o fornecedor de CRM mudar no futuro, só esta classe
    precisa ser reescrita — o contrato com o app (4 ações, mesmo payload)
    não muda.

    A empresa é localizada por uma propriedade customizada de CNPJ no
    objeto Company, cujo nome interno é configurável
    (`settings.crm_cnpj_property_name`) porque ela ainda está sendo
    criada na conta do CRM — não deve ser hardcoded."""

    def __init__(self, client: httpx.AsyncClient | None = None) -> None:
        self._client = client or httpx.AsyncClient(
            base_url=BASE_URL,
            timeout=10.0,
            headers={"Authorization": f"Bearer {settings.crm_token}"},
        )
        self._owner_cache: dict[str, str] = {}

    async def aclose(self) -> None:
        await self._client.aclose()

    async def handle(self, request: CrmRequest) -> dict:
        handlers = {
            "getNotesWithOwners": self.get_notes_with_owners,
            "getContacts": self.get_contacts,
            "addContact": self.add_contact,
            "addNote": self.add_note,
        }
        return await handlers[request.action](request)

    # ─── Leitura ────────────────────────────────────────────────────────

    async def get_notes_with_owners(self, request: CrmRequest) -> dict:
        company_id = await self._find_company_id(request.cnpj)
        if company_id is None:
            return {"notes": []}

        note_ids = await self._associated_ids(company_id, "notes")
        if not note_ids:
            return {"notes": []}

        results = await self._batch_read(
            "notes", note_ids, ["hs_note_body", "hs_timestamp", "hubspot_owner_id"]
        )

        owner_ids = {
            r["properties"].get("hubspot_owner_id")
            for r in results
            if r["properties"].get("hubspot_owner_id")
        }
        for owner_id in owner_ids - self._owner_cache.keys():
            self._owner_cache[owner_id] = await self._owner_name(owner_id)

        notes = [
            {
                "id": r["id"],
                "body": r["properties"].get("hs_note_body") or "",
                "timestamp": _normalize_timestamp(r["properties"]["hs_timestamp"]),
                "ownerName": self._owner_cache.get(
                    r["properties"].get("hubspot_owner_id") or ""
                ),
            }
            for r in results
        ]
        return {"notes": notes}

    async def get_contacts(self, request: CrmRequest) -> dict:
        company_id = await self._find_company_id(request.cnpj)
        if company_id is None:
            return {"contacts": []}

        contact_ids = await self._associated_ids(company_id, "contacts")
        if not contact_ids:
            return {"contacts": []}

        results = await self._batch_read(
            "contacts", contact_ids, ["firstname", "lastname", "phone", "email"]
        )

        contacts = [
            {
                "id": r["id"],
                "nome": " ".join(
                    filter(
                        None,
                        [
                            r["properties"].get("firstname"),
                            r["properties"].get("lastname"),
                        ],
                    )
                ).strip(),
                "telefone": r["properties"].get("phone"),
                "email": r["properties"].get("email"),
            }
            for r in results
        ]
        return {"contacts": contacts}

    # ─── Escrita ────────────────────────────────────────────────────────

    async def add_contact(self, request: CrmRequest) -> dict:
        company_id = await self._find_company_id(request.cnpj)
        if company_id is None:
            raise CrmCompanyNotFoundError(
                f"Nenhuma empresa no CRM com CNPJ {request.cnpj}"
            )

        nome = request.nome or ""
        firstname, _, lastname = nome.partition(" ")
        properties = {
            "firstname": firstname,
            "lastname": lastname,
            "phone": request.telefone,
        }
        if request.email:
            properties["email"] = request.email

        contact = await self._post("/crm/v3/objects/contacts", {"properties": properties})
        await self._associate_default("contacts", contact["id"], "companies", company_id)
        return {}

    async def add_note(self, request: CrmRequest) -> dict:
        company_id = await self._find_company_id(request.cnpj)
        if company_id is None:
            raise CrmCompanyNotFoundError(
                f"Nenhuma empresa no CRM com CNPJ {request.cnpj}"
            )

        properties = {
            "hs_note_body": request.noteText,
            "hs_timestamp": str(int(time.time() * 1000)),
        }
        note = await self._post("/crm/v3/objects/notes", {"properties": properties})
        await self._associate_default("notes", note["id"], "companies", company_id)
        return {}

    # ─── Helpers HTTP ───────────────────────────────────────────────────

    async def _find_company_id(self, cnpj: str) -> str | None:
        body = {
            "filterGroups": [
                {
                    "filters": [
                        {
                            "propertyName": settings.crm_cnpj_property_name,
                            "operator": "EQ",
                            "value": cnpj,
                        }
                    ]
                }
            ],
            "limit": 1,
        }
        data = await self._post("/crm/v3/objects/companies/search", body)
        results = data.get("results") or []
        return results[0]["id"] if results else None

    async def _associated_ids(self, company_id: str, to_object_type: str) -> list[str]:
        data = await self._get(
            f"/crm/v4/objects/companies/{company_id}/associations/{to_object_type}"
        )
        return [r["toObjectId"] for r in data.get("results") or []]

    async def _batch_read(
        self, object_type: str, ids: list[str], properties: list[str]
    ) -> list[dict]:
        body = {"inputs": [{"id": str(i)} for i in ids], "properties": properties}
        data = await self._post(f"/crm/v3/objects/{object_type}/batch/read", body)
        return data.get("results") or []

    async def _owner_name(self, owner_id: str) -> str | None:
        try:
            data = await self._get(f"/crm/v3/owners/{owner_id}")
        except UpstreamIntegrationError:
            return None
        nome = " ".join(filter(None, [data.get("firstName"), data.get("lastName")]))
        return nome.strip() or None

    async def _associate_default(
        self, from_type: str, from_id: str, to_type: str, to_id: str
    ) -> None:
        await self._put(
            f"/crm/v4/objects/{from_type}/{from_id}/associations/default/{to_type}/{to_id}"
        )

    async def _request(self, method: str, path: str, **kwargs) -> dict:
        try:
            response = await self._client.request(method, path, **kwargs)
        except httpx.RequestError as exc:
            raise UpstreamIntegrationError(
                f"Falha de rede ao chamar o CRM ({method} {path}): {exc}"
            ) from exc

        if response.status_code >= 400:
            raise UpstreamIntegrationError(
                f"CRM respondeu {response.status_code} em {method} {path}: {response.text}"
            )
        return response.json() if response.content else {}

    async def _get(self, path: str) -> dict:
        return await self._request("GET", path)

    async def _post(self, path: str, body: dict) -> dict:
        return await self._request("POST", path, json=body)

    async def _put(self, path: str) -> dict:
        return await self._request("PUT", path)
