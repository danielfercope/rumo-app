import json

import httpx
import pytest
import respx

from app.errors import CrmCompanyNotFoundError
from app.schemas import CrmRequest
from app.services.crm_service import BASE_URL, CrmService

CNPJ = "19131243000197"
COMPANY_ID = "company-1"


def _mock_company_search(found: bool = True) -> None:
    results = [{"id": COMPANY_ID}] if found else []
    respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(200, json={"results": results})
    )


@pytest.fixture
def service():
    service = CrmService(client=httpx.AsyncClient(base_url=BASE_URL))
    yield service


@respx.mock
async def test_get_notes_with_owners_sem_empresa_encontrada(service):
    _mock_company_search(found=False)

    result = await service.get_notes_with_owners(
        CrmRequest(group_id="g1", action="getNotesWithOwners", cnpj=CNPJ)
    )

    assert result == {"notes": []}


@respx.mock
async def test_get_notes_with_owners_resolve_nome_do_owner(service):
    _mock_company_search(found=True)
    respx.get(
        f"{BASE_URL}/crm/v4/objects/companies/{COMPANY_ID}/associations/notes"
    ).mock(return_value=httpx.Response(200, json={"results": [{"toObjectId": "n1"}]}))
    respx.post(f"{BASE_URL}/crm/v3/objects/notes/batch/read").mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {
                        "id": "n1",
                        "properties": {
                            "hs_note_body": "Ligação realizada",
                            "hs_timestamp": "1768470000000",
                            "hubspot_owner_id": "owner-1",
                        },
                    }
                ]
            },
        )
    )
    respx.get(f"{BASE_URL}/crm/v3/owners/owner-1").mock(
        return_value=httpx.Response(
            200, json={"firstName": "Fulano", "lastName": "Silva"}
        )
    )

    result = await service.get_notes_with_owners(
        CrmRequest(group_id="g1", action="getNotesWithOwners", cnpj=CNPJ)
    )

    assert result["notes"] == [
        {
            "id": "n1",
            "body": "Ligação realizada",
            "timestamp": "2026-01-15T09:40:00Z",
            "ownerName": "Fulano Silva",
        }
    ]


@respx.mock
async def test_get_notes_with_owners_aceita_timestamp_iso_do_hubspot(service):
    # O HubSpot recebe hs_timestamp como epoch ms na criação, mas devolve
    # ISO-8601 na leitura — confirmado contra a API real.
    _mock_company_search(found=True)
    respx.get(
        f"{BASE_URL}/crm/v4/objects/companies/{COMPANY_ID}/associations/notes"
    ).mock(return_value=httpx.Response(200, json={"results": [{"toObjectId": "n1"}]}))
    respx.post(f"{BASE_URL}/crm/v3/objects/notes/batch/read").mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {
                        "id": "n1",
                        "properties": {
                            "hs_note_body": "Nota de teste",
                            "hs_timestamp": "2026-10-21T00:19:30.863Z",
                            "hubspot_owner_id": None,
                        },
                    }
                ]
            },
        )
    )

    result = await service.get_notes_with_owners(
        CrmRequest(group_id="g1", action="getNotesWithOwners", cnpj=CNPJ)
    )

    assert result["notes"] == [
        {
            "id": "n1",
            "body": "Nota de teste",
            "timestamp": "2026-10-21T00:19:30.863Z",
            "ownerName": None,
        }
    ]


@respx.mock
async def test_get_contacts_concatena_nome(service):
    _mock_company_search(found=True)
    respx.get(
        f"{BASE_URL}/crm/v4/objects/companies/{COMPANY_ID}/associations/contacts"
    ).mock(return_value=httpx.Response(200, json={"results": [{"toObjectId": "c1"}]}))
    respx.post(f"{BASE_URL}/crm/v3/objects/contacts/batch/read").mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {
                        "id": "c1",
                        "properties": {
                            "firstname": "Maria",
                            "lastname": "Souza",
                            "phone": "47999999999",
                            "email": "maria@empresa.com",
                        },
                    }
                ]
            },
        )
    )

    result = await service.get_contacts(CrmRequest(group_id="g1", action="getContacts", cnpj=CNPJ))

    assert result["contacts"] == [
        {
            "id": "c1",
            "nome": "Maria Souza",
            "telefone": "47999999999",
            "email": "maria@empresa.com",
        }
    ]


@respx.mock
async def test_add_contact_sem_empresa_encontrada_lanca_erro(service):
    _mock_company_search(found=False)

    with pytest.raises(CrmCompanyNotFoundError):
        await service.add_contact(
            CrmRequest(
                group_id="g1",
                action="addContact", cnpj=CNPJ, nome="João Pedro", telefone="123"
            )
        )


@respx.mock
async def test_add_contact_cria_e_associa(service):
    _mock_company_search(found=True)
    create_route = respx.post(f"{BASE_URL}/crm/v3/objects/contacts").mock(
        return_value=httpx.Response(201, json={"id": "c2"})
    )
    associate_route = respx.put(
        f"{BASE_URL}/crm/v4/objects/contacts/c2/associations/default/companies/{COMPANY_ID}"
    ).mock(return_value=httpx.Response(204))

    await service.add_contact(
        CrmRequest(group_id="g1", action="addContact", cnpj=CNPJ, nome="João Pedro", telefone="123")
    )

    assert create_route.calls.last.request.content
    assert associate_route.called


@respx.mock
async def test_add_note_cria_e_associa(service):
    _mock_company_search(found=True)
    create_route = respx.post(f"{BASE_URL}/crm/v3/objects/notes").mock(
        return_value=httpx.Response(201, json={"id": "n2"})
    )
    associate_route = respx.put(
        f"{BASE_URL}/crm/v4/objects/notes/n2/associations/default/companies/{COMPANY_ID}"
    ).mock(return_value=httpx.Response(204))

    await service.add_note(
        CrmRequest(group_id="g1", action="addNote", cnpj=CNPJ, noteText="Cliente interessado")
    )

    assert create_route.called
    assert associate_route.called


# ─── Sincronização: busca de empresas novas ────────────────────────────

@respx.mock
async def test_find_new_companies_faz_uma_chamada_filtrada_por_id_e_janela(service):
    route = respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(
            200, json={"results": [{"id": "11", "properties": {"cnpj": CNPJ}}]}
        )
    )

    rows = await service.find_new_companies(after_id=10, since_ms=1000, limit=100)

    assert rows == [{"id": "11", "properties": {"cnpj": CNPJ}}]
    assert route.call_count == 1
    body = json.loads(route.calls.last.request.content)
    by_id, by_date = body["filterGroups"]
    assert {"propertyName": "hs_object_id", "operator": "GT", "value": "10"} in by_id["filters"]
    assert {"propertyName": "createdate", "operator": "GTE", "value": "1000"} in by_date["filters"]
    for group in body["filterGroups"]:
        assert {"propertyName": "cnpj", "operator": "HAS_PROPERTY"} in group["filters"]
    assert body["sorts"] == [{"propertyName": "hs_object_id", "direction": "ASCENDING"}]
    assert body["limit"] == 100


@respx.mock
async def test_find_new_companies_sem_janela_so_filtra_por_id(service):
    route = respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(200, json={"results": []})
    )

    assert await service.find_new_companies(after_id=0, since_ms=None, limit=5) == []

    body = json.loads(route.calls.last.request.content)
    assert len(body["filterGroups"]) == 1


@respx.mock
async def test_latest_company_id(service):
    route = respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(200, json={"results": [{"id": "987"}]})
    )

    assert await service.latest_company_id() == 987
    body = json.loads(route.calls.last.request.content)
    assert body["sorts"] == [{"propertyName": "hs_object_id", "direction": "DESCENDING"}]
    assert body["limit"] == 1


@respx.mock
async def test_latest_company_id_sem_empresas(service):
    respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(200, json={"results": []})
    )

    assert await service.latest_company_id() == 0
