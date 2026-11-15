import json
import httpx
import pytest
import respx

from app.errors import CrmNotAvailableError, CrmPermissionError
from app.schemas import CrmRequest
from app.services.crm_service import BASE_URL, CrmService
from app.services.organization_crm import OrganizationCrm
from app.services.token_cipher import TokenCipher
from cryptography.fernet import Fernet

CIPHER = TokenCipher(Fernet.generate_key().decode())


class FakeDb:
    def __init__(self, conexao=None, crm_object_id=None, empresa=None):
        self.conexao = conexao
        self.crm_object_id = crm_object_id
        self.empresa = empresa
        self.queries = []
        self.updates = []

    async def update(self, table, params, values):
        self.updates.append((table, params, values))

    async def select(self, table, params):
        self.queries.append((table, params))
        if table == "crm_conexoes":
            return [self.conexao] if self.conexao else []
        if table == "carteira_empresas":
            if "company_id" in params["select"]:
                return [{"company_id": "c-1", "companies": self.empresa}] if self.empresa else []
            return [{"crm_object_id": self.crm_object_id, "companies": {"cnpj": "1"}}]
        return []


def _conexao(provedor="hubspot"):
    return {
        "provedor": provedor,
        "token_cifrado": CIPHER.encrypt("tok-da-org"),
        "mapeamento": {"campo_cnpj": "cnpj_empresa"},
    }


async def test_organizacao_conectada_usa_o_proprio_token_e_o_id_guardado(monkeypatch):
    criados = []
    original = CrmService.__init__

    def espiao(self, client=None, *, token=None, cnpj_property=None, **kw):
        criados.append((token, cnpj_property))
        original(self, client, token=token, cnpj_property=cnpj_property, **kw)

    monkeypatch.setattr(CrmService, "__init__", espiao)
    org = OrganizationCrm(FakeDb(_conexao(), crm_object_id="987"), CIPHER)

    async with org.open("g2", "12.345.678/0001-99") as (_, company_id):
        assert company_id == "987"
    assert criados == [("tok-da-org", "cnpj_empresa")]


async def test_empresa_sem_id_no_crm_procura_pelo_cnpj():
    db = FakeDb(_conexao(), crm_object_id=None)
    org = OrganizationCrm(db, CIPHER)
    async with org.open("g2", "12345678000199") as (_, company_id):
        assert company_id is None
    carteira = [p for t, p in db.queries if t == "carteira_empresas"][0]
    assert carteira["companies.cnpj"] == "eq.12345678000199"
    assert carteira["group_id"] == "eq.g2"


async def test_sem_conexao_nao_tem_crm():
    """Não existe conta global pra cair."""
    org = OrganizationCrm(FakeDb(), CIPHER)
    with pytest.raises(CrmNotAvailableError):
        async with org.open("g2", "1"):
            pass


@pytest.mark.parametrize("provedor, cipher", [("outro", CIPHER), ("hubspot", None)])
async def test_conexao_que_nao_da_pra_usar(provedor, cipher):
    org = OrganizationCrm(FakeDb(_conexao(provedor)), cipher)
    with pytest.raises(CrmNotAvailableError):
        async with org.open("g2", "1"):
            pass


@respx.mock
async def test_id_conhecido_nao_busca_pelo_cnpj():
    search = respx.post(f"{BASE_URL}/crm/v3/objects/companies/search")
    respx.get(f"{BASE_URL}/crm/v4/objects/companies/987/associations/contacts").mock(
        return_value=httpx.Response(200, json={"results": []})
    )
    service = CrmService(client=httpx.AsyncClient(base_url=BASE_URL))
    result = await service.handle(
        CrmRequest(group_id="g2", action="getContacts", cnpj="1"), company_id="987"
    )
    assert result == {"contacts": []}
    assert not search.called


@respx.mock
async def test_busca_pelo_cnpj_usa_a_propriedade_do_mapeamento():
    search = respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(200, json={"results": []})
    )
    service = CrmService(
        client=httpx.AsyncClient(base_url=BASE_URL), cnpj_property="cnpj_empresa"
    )
    await service.handle(CrmRequest(group_id="g2", action="getNotesWithOwners", cnpj="1"))
    body = search.calls.last.request.read().decode()
    assert '"propertyName":"cnpj_empresa"' in body.replace(" ", "")


@respx.mock
@pytest.mark.parametrize("status", [401, 403])
async def test_token_sem_permissao_vira_erro_de_permissao(status):
    respx.get(f"{BASE_URL}/crm/v4/objects/companies/987/associations/notes").mock(
        return_value=httpx.Response(status, json={"message": "missing scopes"})
    )
    service = CrmService(client=httpx.AsyncClient(base_url=BASE_URL))
    with pytest.raises(CrmPermissionError):
        await service.handle(
            CrmRequest(group_id="g2", action="getNotesWithOwners", cnpj="1"),
            company_id="987",
        )


_EMPRESA = {
    "cnpj": "04626152000155",
    "nome_fantasia": "BOLD",
    "razao_social": "Bold Ltda",
    "municipio": "Joinville",
    "uf": "SC",
    "telefone_principal": None,
}


@respx.mock
async def test_nota_em_empresa_que_nao_esta_no_crm_cria_a_empresa_e_guarda_o_id():
    respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(200, json={"results": []})
    )
    criar = respx.post(f"{BASE_URL}/crm/v3/objects/companies").mock(
        return_value=httpx.Response(201, json={"id": "555"})
    )
    respx.post(f"{BASE_URL}/crm/v3/objects/notes").mock(
        return_value=httpx.Response(201, json={"id": "n1"})
    )
    associar = respx.put(
        f"{BASE_URL}/crm/v4/objects/notes/n1/associations/default/companies/555"
    ).mock(return_value=httpx.Response(200, json={}))
    db = FakeDb(_conexao(), crm_object_id=None, empresa=_EMPRESA)
    org = OrganizationCrm(db, CIPHER)

    async with org.open("g2", "04.626.152/0001-55") as (service, company_id):
        await service.handle(
            CrmRequest(group_id="g2", action="addNote", cnpj="04.626.152/0001-55",
                       noteText="oi"),
            company_id=company_id,
        )

    props = json.loads(criar.calls.last.request.content)["properties"]
    assert props == {
        "name": "BOLD",
        "cnpj_empresa": "04626152000155",
        "city": "Joinville",
        "state": "SC",
    }
    assert associar.called
    assert db.updates == [
        ("carteira_empresas",
         {"group_id": "eq.g2", "company_id": "eq.c-1"},
         {"crm_object_id": "555"}),
    ]


@respx.mock
async def test_ler_notas_de_empresa_fora_do_crm_nao_cria_nada():
    respx.post(f"{BASE_URL}/crm/v3/objects/companies/search").mock(
        return_value=httpx.Response(200, json={"results": []})
    )
    criar = respx.post(f"{BASE_URL}/crm/v3/objects/companies")
    db = FakeDb(_conexao(), crm_object_id=None, empresa=_EMPRESA)
    org = OrganizationCrm(db, CIPHER)

    async with org.open("g2", "04626152000155") as (service, company_id):
        r = await service.handle(
            CrmRequest(group_id="g2", action="getNotesWithOwners",
                       cnpj="04626152000155"),
            company_id=company_id,
        )
    assert r == {"notes": []}
    assert not criar.called
    assert db.updates == []
