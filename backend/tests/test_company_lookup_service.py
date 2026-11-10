import httpx
import pytest
import respx

from app.errors import CnpjNotFoundError, UpstreamIntegrationError
from app.services.company_lookup_service import BASE_URL, CompanyLookupService

# Shape real confirmado contra a BrasilAPI (GET /api/cnpj/v1/{cnpj}) em
# 2026-10-18, pra uma empresa real — ver plano de implementação.
SAMPLE_RESPONSE = {
    "cnpj": "19131243000197",
    "razao_social": "OPEN KNOWLEDGE BRASIL",
    "nome_fantasia": "REDE PELO CONHECIMENTO LIVRE",
    "email": None,
    "ddd_telefone_1": "1123851939",
    "descricao_tipo_de_logradouro": "AVENIDA",
    "logradouro": "PAULISTA",
    "numero": "37",
    "bairro": "BELA VISTA",
    "municipio": "SAO PAULO",
    "uf": "SP",
    "cep": "01311902",
    "descricao_situacao_cadastral": "ATIVA",
    "porte": "DEMAIS",
    "cnae_fiscal_descricao": "Atividades de associações de defesa de direitos sociais",
    "natureza_juridica": "Associação Privada",
    "data_inicio_atividade": "2013-10-03",
}


@pytest.fixture
def service():
    service = CompanyLookupService()
    yield service


@respx.mock
async def test_lookup_cnpj_mapeia_para_o_shape_legado(service):
    respx.get(f"{BASE_URL}/19131243000197").mock(
        return_value=httpx.Response(200, json=SAMPLE_RESPONSE)
    )

    result = await service.lookup_cnpj("19.131.243/0001-97")

    assert result["cnpj"] == "19131243000197"
    assert result["razao"] == "OPEN KNOWLEDGE BRASIL"
    assert result["fantasia"] == "REDE PELO CONHECIMENTO LIVRE"
    assert result["ddd_1"] == "11"
    assert result["tel_1"] == "23851939"
    assert result["log_tipo"] == "AVENIDA"
    assert result["log_nome"] == "PAULISTA"
    assert result["log_num"] == "37"
    assert result["situacao_cadastral"] == "ATIVA"
    assert result["porte"] == "DEMAIS"
    assert result["data_abertura"] == "20131003"
    assert result["site"] is None


@respx.mock
async def test_lookup_cnpj_404_lanca_cnpj_not_found(service):
    respx.get(f"{BASE_URL}/00000000000000").mock(
        return_value=httpx.Response(
            404, json={"message": "não encontrado", "name": "NotFoundError"}
        )
    )

    with pytest.raises(CnpjNotFoundError):
        await service.lookup_cnpj("00000000000000")


@respx.mock
async def test_lookup_cnpj_erro_de_rede_lanca_upstream_error(service):
    respx.get(f"{BASE_URL}/19131243000197").mock(
        side_effect=httpx.ConnectError("timeout")
    )

    with pytest.raises(UpstreamIntegrationError):
        await service.lookup_cnpj("19131243000197")
