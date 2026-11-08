import json

import httpx
import pytest
import respx

from app.errors import InvalidCrmTokenError, UpstreamIntegrationError
from app.services import crm_connector
from app.services.crm_connector import (
    HUBSPOT_BASE_URL,
    CrmMapping,
    HubSpotConnector,
    build_connector,
)

SEARCH_URL = f"{HUBSPOT_BASE_URL}/crm/v3/objects/companies/search"
MAPPING = CrmMapping()


@pytest.fixture
def connector():
    return HubSpotConnector(
        "token", client=httpx.AsyncClient(base_url=HUBSPOT_BASE_URL)
    )


def _row(id_, cnpj, stage="lead", modified="2024-05-01T10:00:00.000Z"):
    return {
        "id": str(id_),
        "properties": {
            "cnpj": cnpj,
            "lifecyclestage": stage,
            "hs_lastmodifieddate": modified,
        },
    }


async def _collect(connector, since_ms=None, mapping=MAPPING):
    pages = []
    async for page in connector.fetch_changes(since_ms, mapping):
        pages.append(page)
    return pages


# ─── Mapeamento ─────────────────────────────────────────────────────────


def test_mapeamento_padrao_do_hubspot():
    m = CrmMapping.from_json(None)

    assert m.campo_cnpj == "cnpj"
    assert m.resolve_status("customer") == "cliente"
    assert m.resolve_status("EVANGELIST") == "cliente"
    assert m.resolve_status("opportunity") == "lead"
    assert m.resolve_status(None) == "lead"


def test_mapeamento_customizado_define_perdido():
    m = CrmMapping.from_json(
        {
            "campo_cnpj": "cnpj_empresa",
            "campo_status": "situacao_comercial",
            "status": {"cliente": ["Ativo"], "perdido": ["Churn", "Perdido"]},
        }
    )

    assert m.campo_cnpj == "cnpj_empresa"
    assert m.resolve_status("ativo") == "cliente"
    assert m.resolve_status("churn") == "perdido"
    assert m.resolve_status("customer") == "lead"  # padrão não vaza pro custom


# ─── validate / list_properties ─────────────────────────────────────────


@respx.mock
async def test_validate_aceita_token_valido(connector):
    route = respx.get(f"{HUBSPOT_BASE_URL}/crm/v3/objects/companies").mock(
        return_value=httpx.Response(200, json={"results": []})
    )

    await connector.validate()

    assert route.calls.last.request.url.params["limit"] == "1"


@pytest.mark.parametrize("status", [401, 403])
@respx.mock
async def test_validate_token_recusado(connector, status):
    respx.get(f"{HUBSPOT_BASE_URL}/crm/v3/objects/companies").mock(
        return_value=httpx.Response(status, json={"message": "nope"})
    )

    with pytest.raises(InvalidCrmTokenError):
        await connector.validate()


@respx.mock
async def test_erro_do_crm_vira_falha_de_integracao(connector):
    respx.get(f"{HUBSPOT_BASE_URL}/crm/v3/objects/companies").mock(
        return_value=httpx.Response(500, text="boom")
    )

    with pytest.raises(UpstreamIntegrationError):
        await connector.validate()


@respx.mock
async def test_list_properties_ignora_arquivadas(connector):
    respx.get(f"{HUBSPOT_BASE_URL}/crm/v3/properties/companies").mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {"name": "cnpj", "label": "CNPJ", "type": "string"},
                    {"name": "velha", "label": "Velha", "type": "string", "archived": True},
                    {"name": "lifecyclestage", "type": "enumeration"},
                ]
            },
        )
    )

    props = await connector.list_properties()

    assert [(p.name, p.label) for p in props] == [
        ("cnpj", "CNPJ"),
        ("lifecyclestage", "lifecyclestage"),
    ]


# ─── fetch_changes ──────────────────────────────────────────────────────


@respx.mock
async def test_fetch_changes_carga_inicial_sem_filtro_de_data(connector):
    route = respx.post(SEARCH_URL).mock(
        return_value=httpx.Response(
            200, json={"results": [_row(1, "19.131.243/0001-97", "customer")]}
        )
    )

    pages = await _collect(connector)

    body = json.loads(route.calls.last.request.content)
    filters = body["filterGroups"][0]["filters"]
    assert filters == [{"propertyName": "cnpj", "operator": "HAS_PROPERTY"}]
    assert body["sorts"] == [
        {"propertyName": "hs_lastmodifieddate", "direction": "ASCENDING"}
    ]
    assert body["properties"] == ["cnpj", "lifecyclestage", "hs_lastmodifieddate"]
    record = pages[0][0]
    assert (record.external_id, record.cnpj, record.status_value) == (
        "1",
        "19.131.243/0001-97",
        "customer",
    )
    assert record.modified_at_ms == 1714557600000


@respx.mock
async def test_fetch_changes_incremental_filtra_por_modificacao(connector):
    route = respx.post(SEARCH_URL).mock(
        return_value=httpx.Response(200, json={"results": []})
    )

    pages = await _collect(connector, since_ms=1714557600000)

    assert pages == []
    filters = json.loads(route.calls.last.request.content)["filterGroups"][0]["filters"]
    assert {
        "propertyName": "hs_lastmodifieddate",
        "operator": "GTE",
        "value": "1714557600000",
    } in filters


@respx.mock
async def test_fetch_changes_usa_propriedades_do_mapeamento(connector):
    route = respx.post(SEARCH_URL).mock(
        return_value=httpx.Response(200, json={"results": []})
    )
    mapping = CrmMapping(campo_cnpj="cnpj_empresa", campo_status="situacao")

    await _collect(connector, mapping=mapping)

    body = json.loads(route.calls.last.request.content)
    assert body["filterGroups"][0]["filters"][0]["propertyName"] == "cnpj_empresa"
    assert body["properties"][:2] == ["cnpj_empresa", "situacao"]


@respx.mock
async def test_fetch_changes_pagina_pelo_cursor_after(connector):
    route = respx.post(SEARCH_URL).mock(
        side_effect=[
            httpx.Response(
                200,
                json={"results": [_row(1, "1")], "paging": {"next": {"after": "100"}}},
            ),
            httpx.Response(200, json={"results": [_row(2, "2")]}),
        ]
    )

    pages = await _collect(connector)

    assert [[r.external_id for r in p] for p in pages] == [["1"], ["2"]]
    assert "after" not in json.loads(route.calls[0].request.content)
    assert json.loads(route.calls[1].request.content)["after"] == "100"


@respx.mock
async def test_fetch_changes_reinicia_a_partir_da_ultima_modificacao_no_teto(
    connector, monkeypatch
):
    monkeypatch.setattr(crm_connector, "HUBSPOT_MAX_PAGES_PER_QUERY", 2)
    route = respx.post(SEARCH_URL).mock(
        side_effect=[
            httpx.Response(
                200,
                json={
                    "results": [_row(1, "1", modified="2024-05-01T10:00:00.000Z")],
                    "paging": {"next": {"after": "a"}},
                },
            ),
            httpx.Response(
                200,
                json={
                    "results": [_row(2, "2", modified="2024-05-01T11:00:00.000Z")],
                    "paging": {"next": {"after": "b"}},
                },
            ),
            httpx.Response(
                200,
                json={"results": [_row(3, "3", modified="2024-05-01T12:00:00.000Z")]},
            ),
        ]
    )

    pages = await _collect(connector)

    assert [p[0].external_id for p in pages] == ["1", "2", "3"]
    restart = json.loads(route.calls[2].request.content)
    assert "after" not in restart
    gte = [
        f for f in restart["filterGroups"][0]["filters"] if f["operator"] == "GTE"
    ][0]
    assert gte["value"] == "1714561200000"  # modificação do último registro (11:00Z)


@respx.mock
async def test_fetch_changes_para_se_o_reinicio_nao_progride(connector, monkeypatch):
    monkeypatch.setattr(crm_connector, "HUBSPOT_MAX_PAGES_PER_QUERY", 1)
    respx.post(SEARCH_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [_row(1, "1", modified="2024-05-01T10:00:00.000Z")],
                "paging": {"next": {"after": "a"}},
            },
        )
    )

    pages = await _collect(connector)

    assert len(pages) == 2  # a 1ª consulta e UM reinício; o 2º não avança e encerra


@respx.mock
async def test_fetch_changes_propaga_token_recusado(connector):
    respx.post(SEARCH_URL).mock(return_value=httpx.Response(401, json={}))

    with pytest.raises(InvalidCrmTokenError):
        await _collect(connector)


def test_build_connector_hubspot_e_desconhecido():
    assert isinstance(build_connector("hubspot", "t"), HubSpotConnector)
    with pytest.raises(ValueError):
        build_connector("pipedrive", "t")
