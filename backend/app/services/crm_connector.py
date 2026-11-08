"""Conectores de CRM por organização: cada um lê, com o token da própria
organização, as empresas (CNPJ + status) que alimentam a carteira dela.

Só dados de EMPRESA são lidos — nunca contatos, notas ou negócios (minimização
de dados, LGPD). A interface é pequena de propósito: um novo CRM (Pipedrive, RD
Station...) só precisa implementar `CrmConnector`; o restante (carteira, ETL de
CNPJ, scoring) não muda."""

from collections.abc import AsyncIterator, Callable, Mapping
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Protocol

import httpx

from ..errors import InvalidCrmTokenError, UpstreamIntegrationError

HUBSPOT_BASE_URL = "https://api.hubapi.com"

# A Search API do HubSpot devolve no máximo 10.000 resultados por consulta e
# 100 por página; paramos antes disso e reiniciamos a partir da data de
# modificação do último registro.
HUBSPOT_PAGE_SIZE = 100
HUBSPOT_MAX_PAGES_PER_QUERY = 99

STATUSES = ("cliente", "lead", "perdido")


@dataclass(frozen=True)
class CrmProperty:
    name: str
    label: str
    type: str


@dataclass(frozen=True)
class CrmRecord:
    external_id: str
    cnpj: str | None  # como veio do CRM (com ou sem máscara)
    status_value: str | None  # valor bruto do campo de status
    modified_at_ms: int


@dataclass(frozen=True)
class CrmMapping:
    """Como ler as empresas de um CRM: qual propriedade guarda o CNPJ, qual
    guarda o estágio e que valores do estágio significam cliente/perdido
    (todo o resto é lead). Vem de crm_conexoes.mapeamento (jsonb)."""

    campo_cnpj: str = "cnpj"
    campo_status: str = "lifecyclestage"
    valores_cliente: tuple[str, ...] = ("customer", "evangelist")
    valores_perdido: tuple[str, ...] = ()

    @classmethod
    def from_json(cls, data: Mapping | None) -> "CrmMapping":
        data = data or {}
        status = data.get("status") or {}
        defaults = cls()
        return cls(
            campo_cnpj=data.get("campo_cnpj") or defaults.campo_cnpj,
            campo_status=data.get("campo_status") or defaults.campo_status,
            valores_cliente=tuple(status.get("cliente", defaults.valores_cliente)),
            valores_perdido=tuple(status.get("perdido", defaults.valores_perdido)),
        )

    def resolve_status(self, raw: str | None) -> str:
        value = (raw or "").strip().lower()
        if value and value in {v.lower() for v in self.valores_cliente}:
            return "cliente"
        if value and value in {v.lower() for v in self.valores_perdido}:
            return "perdido"
        return "lead"


class CrmConnector(Protocol):
    async def validate(self) -> None:
        """Levanta InvalidCrmTokenError se o CRM recusar o token."""

    async def list_properties(self) -> list[CrmProperty]:
        """Propriedades de empresa disponíveis, pra o usuário mapear CNPJ/status."""

    def fetch_changes(
        self, since_ms: int | None, mapping: CrmMapping
    ) -> AsyncIterator[list[CrmRecord]]:
        """Empresas com CNPJ criadas/alteradas desde `since_ms` (None = todas),
        em ordem crescente de modificação, em páginas."""

    async def aclose(self) -> None: ...


def _iso_to_ms(value: str | None) -> int:
    if not value:
        return 0
    try:
        return int(float(value))  # epoch ms
    except ValueError:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp() * 1000)


@dataclass
class HubSpotConnector:
    token: str
    client: httpx.AsyncClient | None = None
    _owns_client: bool = field(init=False, default=False)

    def __post_init__(self) -> None:
        if self.client is None:
            self.client = httpx.AsyncClient(
                base_url=HUBSPOT_BASE_URL,
                timeout=10.0,
                headers={"Authorization": f"Bearer {self.token}"},
            )
            self._owns_client = True

    async def aclose(self) -> None:
        if self._owns_client:
            await self.client.aclose()

    async def validate(self) -> None:
        await self._request("GET", "/crm/v3/objects/companies", params={"limit": 1})

    async def list_properties(self) -> list[CrmProperty]:
        data = await self._request("GET", "/crm/v3/properties/companies")
        return [
            CrmProperty(
                name=p["name"],
                label=p.get("label") or p["name"],
                type=p.get("type") or "string",
            )
            for p in data.get("results") or []
            if not p.get("archived")
        ]

    async def fetch_changes(
        self, since_ms: int | None, mapping: CrmMapping
    ) -> AsyncIterator[list[CrmRecord]]:
        cursor = since_ms
        while True:
            last_modified = cursor or 0
            after: str | None = None
            pages = 0
            while True:
                data = await self._request(
                    "POST",
                    "/crm/v3/objects/companies/search",
                    json=self._search_body(cursor, mapping, after),
                )
                records = [
                    self._to_record(row, mapping) for row in data.get("results") or []
                ]
                if records:
                    last_modified = records[-1].modified_at_ms
                    yield records

                after = ((data.get("paging") or {}).get("next") or {}).get("after")
                pages += 1
                if not after:
                    return
                if pages >= HUBSPOT_MAX_PAGES_PER_QUERY:
                    break

            if last_modified == (cursor or 0):
                return  # sem progresso: evita laço infinito num teto de 10.000
            cursor = last_modified

    @staticmethod
    def _search_body(
        since_ms: int | None, mapping: CrmMapping, after: str | None
    ) -> dict:
        filters = [{"propertyName": mapping.campo_cnpj, "operator": "HAS_PROPERTY"}]
        if since_ms is not None:
            filters.append(
                {
                    "propertyName": "hs_lastmodifieddate",
                    "operator": "GTE",
                    "value": str(since_ms),
                }
            )
        body: dict = {
            "filterGroups": [{"filters": filters}],
            "sorts": [
                {"propertyName": "hs_lastmodifieddate", "direction": "ASCENDING"}
            ],
            "properties": [
                mapping.campo_cnpj,
                mapping.campo_status,
                "hs_lastmodifieddate",
            ],
            "limit": HUBSPOT_PAGE_SIZE,
        }
        if after:
            body["after"] = after
        return body

    @staticmethod
    def _to_record(row: dict, mapping: CrmMapping) -> CrmRecord:
        props = row.get("properties") or {}
        return CrmRecord(
            external_id=str(row["id"]),
            cnpj=props.get(mapping.campo_cnpj),
            status_value=props.get(mapping.campo_status),
            modified_at_ms=_iso_to_ms(props.get("hs_lastmodifieddate")),
        )

    async def _request(self, method: str, path: str, **kwargs) -> dict:
        try:
            response = await self.client.request(method, path, **kwargs)
        except httpx.RequestError as exc:
            raise UpstreamIntegrationError(
                f"Falha de rede ao chamar o CRM ({method} {path}): {exc}"
            ) from exc

        if response.status_code in (401, 403):
            raise InvalidCrmTokenError(
                "O CRM recusou o token (inválido, revogado ou sem permissão de "
                "leitura de empresas)."
            )
        if response.status_code >= 400:
            raise UpstreamIntegrationError(
                f"CRM respondeu {response.status_code} em {method} {path}: "
                f"{response.text}"
            )
        return response.json() if response.content else {}


ConnectorFactory = Callable[[str, str], CrmConnector]


def build_connector(provedor: str, token: str) -> CrmConnector:
    if provedor == "hubspot":
        return HubSpotConnector(token)
    raise ValueError(f"Provedor de CRM não suportado: {provedor}")
