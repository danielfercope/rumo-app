from datetime import date, datetime, timedelta, timezone

import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from app import main
from app.errors import CompanyNotInPortfolioError, NotGroupMemberError
from app.internal_token import mint_internal_token
from app.services.enrichment import compras, google_places, receita, regional
from app.services.enrichment.base import SourceNotFound, SourceUnavailable
from app.services.enrichment.service import EnrichmentService

CNPJ = "07175725000160"
IBGE = 4208906


def brasilapi_payload(**over):
    base = {
        "cnpj": CNPJ,
        "razao_social": "WEG EQUIPAMENTOS ELETRICOS S/A",
        "nome_fantasia": "",
        "identificador_matriz_filial": 1,
        "descricao_situacao_cadastral": "ATIVA",
        "data_situacao_cadastral": "2004-10-25",
        "descricao_motivo_situacao_cadastral": "SEM MOTIVO",
        "data_inicio_atividade": "2004-10-25",
        "porte": "DEMAIS",
        "natureza_juridica": "Sociedade Anônima Fechada",
        "capital_social": 9350000000,
        "cnae_fiscal": 7020400,
        "cnae_fiscal_descricao": "Consultoria em gestão empresarial",
        "cnaes_secundarios": [
            {"codigo": 2710401, "descricao": "Fabricação de geradores"},
            {"codigo": 0, "descricao": ""},
        ],
        "opcao_pelo_simples": False,
        "data_opcao_pelo_simples": None,
        "data_exclusao_do_simples": None,
        "opcao_pelo_mei": False,
        "regime_tributario": [
            {"ano": 2023, "forma_de_tributacao": "LUCRO REAL"},
            {"ano": 2024, "forma_de_tributacao": "LUCRO REAL"},
        ],
        "qsa": [
            {
                "nome_socio": "ALBERTO KUBA",
                "qualificacao_socio": "Diretor",
                "data_entrada_sociedade": "2020-02-04",
                "faixa_etaria": "Entre 41 a 50 anos",
                "identificador_de_socio": 2,
            },
            {"nome_socio": "", "identificador_de_socio": 2},
        ],
        "descricao_tipo_de_logradouro": "AVENIDA",
        "logradouro": "PREFEITO WALDEMAR GRUBBA",
        "numero": "3000",
        "complemento": "",
        "bairro": "VILA LALAU",
        "municipio": "JARAGUA DO SUL",
        "uf": "SC",
        "cep": "89256-900",
        "codigo_municipio_ibge": IBGE,
        "ddd_telefone_1": "4732764775",
        "ddd_telefone_2": "",
        "email": "CONTATO@WEG.NET",
    }
    base.update(over)
    return base


# ─── Receita ────────────────────────────────────────────────────────────


@respx.mock
async def test_receita_normaliza_o_cadastro():
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    async with httpx.AsyncClient() as c:
        r = await receita.fetch(c, CNPJ)

    assert r["origem"] == "BrasilAPI"
    assert r["nome_fantasia"] is None and r["matriz"] is True
    assert r["situacao"] == {"descricao": "ATIVA", "desde": "2004-10-25", "motivo": "SEM MOTIVO"}
    assert r["capital_social"] == 9_350_000_000
    assert r["cnae_principal"] == {"codigo": "70.20-4/00", "descricao": "Consultoria em gestão empresarial"}
    assert [c["codigo"] for c in r["cnaes_secundarios"]] == ["27.10-4/01"]  # vazio fora
    assert [x["ano"] for x in r["regime_tributario"]] == [2024, 2023]  # mais recente primeiro
    assert r["socios"] == [
        {
            "nome": "ALBERTO KUBA",
            "qualificacao": "Diretor",
            "desde": "2020-02-04",
            "faixa_etaria": "Entre 41 a 50 anos",
            "tipo": "PF",
        }
    ]
    assert r["telefones"] == ["(47) 3276-4775"]
    assert r["email"] == "contato@weg.net"
    assert r["endereco"]["logradouro"] == "AVENIDA PREFEITO WALDEMAR GRUBBA"
    assert r["endereco"]["complemento"] is None and r["endereco"]["cep"] == "89256900"
    assert r["codigo_municipio_ibge"] == IBGE


@respx.mock
async def test_receita_usa_o_minha_receita_quando_a_brasilapi_cai():
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(503)
    respx.get(receita.MINHA_RECEITA_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    async with httpx.AsyncClient() as c:
        r = await receita.fetch(c, CNPJ)
    assert r["origem"] == "Minha Receita"


@respx.mock
async def test_receita_cnpj_inexistente_e_fonte_fora():
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(404)
    respx.get(receita.MINHA_RECEITA_URL.format(cnpj=CNPJ)).respond(404)
    async with httpx.AsyncClient() as c:
        with pytest.raises(SourceNotFound):
            await receita.fetch(c, CNPJ)

    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(500)
    respx.get(receita.MINHA_RECEITA_URL.format(cnpj=CNPJ)).mock(
        side_effect=httpx.ConnectTimeout("lento"))
    async with httpx.AsyncClient() as c:
        with pytest.raises(SourceUnavailable):
            await receita.fetch(c, CNPJ)


# ─── Compras públicas ──────────────────────────────────────────────────


def item(controle, valor, data="2026-05-10", cancelado=None, fornecedor=CNPJ, orgao="111", uf="PR"):
    return {
        "niFornecedor": fornecedor,
        "numeroControlePNCPCompra": controle,
        "orgaoEntidadeCnpj": orgao,
        "unidadeOrgaoUfSigla": uf,
        "valorTotalHomologado": valor,
        "dataResultadoPncp": f"{data}T00:00:00",
        "dataCancelamentoPncp": cancelado,
    }


@respx.mock
async def test_compras_soma_ranqueia_e_detalha_as_maiores():
    hoje = date(2026, 11, 12)

    def resultados(request):
        params = dict(request.url.params)
        assert params["niFornecedor"] == CNPJ
        if params["dataResultadoPncpFinal"] == "2026-11-12":  # últimos 12 meses
            return httpx.Response(200, json={"paginasRestantes": 0, "resultado": [
                item("11111111000111-1-000010/2026", 1000.0, orgao="111"),
                item("11111111000111-1-000010/2026", 500.0, data="2026-06-01", orgao="111"),
                item("22222222000122-1-000003/2026", 9000.0, orgao="222", uf="SC"),
                item("33333333000133-1-000001/2026", 99999.0, cancelado="2026-07-01", orgao="333"),
                item("44444444000144-1-000001/2026", 50.0, fornecedor="00000000000000"),
            ]})
        return httpx.Response(200, json={"paginasRestantes": 0, "resultado": [
            item("55555555000155-1-000001/2025", 300.0, orgao="555")]})

    respx.get(compras.RESULTADOS).mock(side_effect=resultados)
    respx.get(compras.FORNECEDOR).respond(200, json={"resultado": [{"habilitadoLicitar": True}]})
    respx.get("https://pncp.gov.br/api/consulta/v1/orgaos/22222222000122/compras/2026/3").respond(
        200, json={"orgaoEntidade": {"razaoSocial": "PREFEITURA DE JOINVILLE"},
                   "unidadeOrgao": {"ufSigla": "SC", "municipioNome": "Joinville"},
                   "objetoCompra": "Motores elétricos", "modalidadeNome": "Pregão - Eletrônico"})
    respx.get("https://pncp.gov.br/api/consulta/v1/orgaos/11111111000111/compras/2026/10").respond(500)

    async with httpx.AsyncClient() as c:
        out = await compras.fetch(c, CNPJ, today=hoje)

    assert out["sicaf"] == {"cadastrado": True, "habilitado": True}
    recent = out["ultimos_12_meses"]
    # cancelado e item de outro fornecedor ficam fora
    assert (recent["itens"], recent["contratacoes"], recent["orgaos"], recent["valor"]) == (3, 2, 2, 10500.0)
    assert recent["ufs"] == ["PR", "SC"]
    assert out["12_meses_anteriores"]["valor"] == 300.0
    first, second = out["contratacoes"]
    assert first["orgao"] == "PREFEITURA DE JOINVILLE" and first["valor"] == 9000.0
    assert first["modalidade"] == "Pregão - Eletrônico"
    assert first["url"] == "https://pncp.gov.br/app/editais/22222222000122/2026/3"
    # detalhe que falhou não derruba: fica sem nome de órgão, com o resto
    assert second["orgao"] is None and second["valor"] == 1500.0 and second["itens"] == 2
    assert second["data"] == "2026-06-01"


@respx.mock
async def test_compras_sem_vendas_e_fonte_fora():
    respx.get(compras.RESULTADOS).respond(200, json={"paginasRestantes": 0, "resultado": []})
    respx.get(compras.FORNECEDOR).respond(200, json={"resultado": []})
    async with httpx.AsyncClient() as c:
        out = await compras.fetch(c, CNPJ, today=date(2026, 11, 12))
    assert out["sicaf"] == {"cadastrado": False, "habilitado": False}
    assert out["ultimos_12_meses"]["itens"] == 0 and out["contratacoes"] == []

    respx.get(compras.RESULTADOS).respond(502)
    async with httpx.AsyncClient() as c:
        with pytest.raises(SourceUnavailable):
            await compras.fetch(c, CNPJ, today=date(2026, 11, 12))


# ─── Regionais ──────────────────────────────────────────────────────────


@respx.mock
async def test_comex_cai_para_o_ano_anterior_e_calcula_participacao():
    def comex(request):
        body = httpx.Request("POST", "x", content=request.content).read()
        import json

        q = json.loads(body)
        year = q["period"]["from"][:4]
        if year == "2025":
            return httpx.Response(200, json={"success": True, "data": {"list": []}})
        detail = q["details"][0]
        rows = (
            [{"headingCode": "8501", "heading": "Motores", "metricFOB": "750"},
             {"headingCode": "8504", "heading": "Transformadores", "metricFOB": "250"}]
            if detail == "heading"
            else [{"country": "China", "metricFOB": "600"}, {"country": "EUA", "metricFOB": "400"}]
        )
        return httpx.Response(200, json={"success": True, "data": {"list": rows}})

    respx.post(regional.COMEX_URL).mock(side_effect=comex)
    async with httpx.AsyncClient() as c:
        out = await regional.comex(c, IBGE, today=date(2026, 11, 12))

    assert out["ano"] == 2024
    assert out["exportacao"]["total_usd"] == 1000
    assert out["exportacao"]["produtos"][0] == {
        "codigo": "8501", "nome": "Motores", "usd": 750.0, "participacao": 0.75}
    assert out["importacao"]["paises"][0]["nome"] == "China"


@respx.mock
async def test_comex_sem_registro_em_dois_anos():
    respx.post(regional.COMEX_URL).respond(200, json={"success": True, "data": {"list": []}})
    async with httpx.AsyncClient() as c:
        with pytest.raises(SourceNotFound):
            await regional.comex(c, IBGE, today=date(2026, 11, 12))


@respx.mock
async def test_ibge_pib_per_capita_usa_a_populacao_do_ano_mais_proximo():
    def serie(values):
        return [{"resultados": [{"series": [{"serie": values}]}]}]

    respx.get(url__regex=r".*/agregados/6579/.*").respond(
        200, json=serie({"2021": "190000", "2024": "200000", "2025": "202000"}))
    respx.get(url__regex=r".*/agregados/5938/.*").respond(
        200, json=serie({"2023": "15000000"}))
    async with httpx.AsyncClient() as c:
        out = await regional.municipio(c, IBGE)

    assert out["populacao"] == {"valor": 202000.0, "ano": "2025"}
    assert out["nome_ibge"] is None  # a resposta de teste não traz localidade
    assert out["pib"] == {"valor": 15_000_000_000.0, "ano": "2023"}
    # 2023 não tem estimativa: usa 2024 (mais próximo)
    assert out["pib_per_capita"] == {"valor": 75000.0, "ano": "2023"}


# ─── Google ─────────────────────────────────────────────────────────────


def test_aberto_agora_pelos_periodos():
    seg_a_sex = [
        {"abre": {"dia": d, "hora": 7, "minuto": 30}, "fecha": {"dia": d, "hora": 17, "minuto": 0}}
        for d in range(1, 6)
    ]
    quarta_10h = datetime(2026, 11, 11, 10, 0)  # quarta
    quarta_18h = datetime(2026, 11, 11, 18, 0)
    domingo = datetime(2026, 11, 15, 10, 0)
    assert google_places.is_open(seg_a_sex, quarta_10h) is True
    assert google_places.is_open(seg_a_sex, quarta_18h) is False
    assert google_places.is_open(seg_a_sex, domingo) is False
    assert google_places.is_open([], quarta_10h) is None
    # 24 h (sem fechamento) e madrugada que atravessa a semana
    assert google_places.is_open([{"abre": {"dia": 0, "hora": 0, "minuto": 0}, "fecha": None}], domingo)
    sab_noite = [{"abre": {"dia": 6, "hora": 22, "minuto": 0}, "fecha": {"dia": 0, "hora": 2, "minuto": 0}}]
    assert google_places.is_open(sab_noite, datetime(2026, 11, 15, 1, 0)) is True  # domingo 1h


@respx.mock
async def test_google_le_o_lugar_e_puxa_a_busca_pra_perto_da_empresa():
    route = respx.post(google_places.SEARCH_URL).respond(200, json={"places": [{
        "id": "PID1",
        "photos": [{"name": "places/PID1/photos/F1", "authorAttributions": [
            {"displayName": "Alexandre", "uri": "https://maps.google.com/contrib/1"}]}],
        "displayName": {"text": "WEG S/A"}, "rating": 4.7, "userRatingCount": 405,
        "nationalPhoneNumber": "(47) 3276-4000", "websiteUri": "http://www.weg.net/",
        "googleMapsUri": "https://maps.google.com/?cid=1", "businessStatus": "OPERATIONAL",
        "regularOpeningHours": {"weekdayDescriptions": ["segunda-feira: 07:30–17:00"],
                                "periods": [{"open": {"day": 1, "hour": 7, "minute": 30},
                                             "close": {"day": 1, "hour": 17, "minute": 0}}]},
    }]})
    async with httpx.AsyncClient() as c:
        g = await google_places.search(c, "chave", "WEG", "Jaraguá do Sul", "SC", -26.4, -49.0)

    body = route.calls[0].request
    assert body.headers["X-Goog-Api-Key"] == "chave"
    import json

    sent = json.loads(body.content)
    assert sent["textQuery"] == "WEG Jaraguá do Sul SC"
    assert sent["locationBias"]["circle"]["center"] == {"latitude": -26.4, "longitude": -49.0}
    assert (g["nome"], g["nota"], g["avaliacoes"], g["situacao"]) == ("WEG S/A", 4.7, 405, "Em funcionamento")
    assert g["periodos"] == [{"abre": {"dia": 1, "hora": 7, "minuto": 30},
                              "fecha": {"dia": 1, "hora": 17, "minuto": 0}}]
    assert g["place_id"] == "PID1"
    assert g["_foto"] == {"ref": "places/PID1/photos/F1", "autor": "Alexandre",
                          "autor_url": "https://maps.google.com/contrib/1"}
    assert "places.photos" in body.headers["X-Goog-FieldMask"]


@respx.mock
async def test_google_sem_resultado_ou_recusado():
    respx.post(google_places.SEARCH_URL).respond(200, json={})
    async with httpx.AsyncClient() as c:
        with pytest.raises(SourceNotFound):
            await google_places.search(c, "k", "X", None, None)
    respx.post(google_places.SEARCH_URL).respond(403, json={"error": {"message": "segredo"}})
    async with httpx.AsyncClient() as c:
        with pytest.raises(SourceUnavailable) as err:
            await google_places.search(c, "k", "X", None, None)
    assert "segredo" not in str(err.value)


# ─── Serviço: acesso e cache ────────────────────────────────────────────


class FakeDb:
    def __init__(self):
        self.cache: dict[tuple[str, str], dict] = {}
        self.companies = [{"cnpj": CNPJ, "razao_social": "WEG EQUIP", "nome_fantasia": None,
                           "municipio": "JARAGUA DO SUL", "uf": "SC",
                           "latitude": "-26.4", "longitude": "-49.0"}]

    async def select(self, table, params):
        if table == "enriquecimento_cache":
            key = (params["fonte"][3:], params["chave"][3:])
            row = self.cache.get(key)
            return [dict(row)] if row else []
        if table == "companies":
            return [c for c in self.companies if c["cnpj"] == params["cnpj"][3:]]
        raise AssertionError(table)

    async def upsert(self, table, rows, on_conflict):
        assert table == "enriquecimento_cache" and on_conflict == "fonte,chave"
        for r in rows:
            self.cache[(r["fonte"], r["chave"])] = {"dados": r["dados"], "buscado_em": r["buscado_em"]}


class FakeAccess:
    def __init__(self):
        self.member, self.in_portfolio, self.calls = True, True, []

    async def require_member(self, uid, group_id):
        self.calls.append(("member", uid, group_id))
        if not self.member:
            raise NotGroupMemberError("fora")

    async def require_cnpj_in_portfolio(self, group_id, cnpj):
        self.calls.append(("portfolio", group_id, cnpj))
        if not self.in_portfolio:
            raise CompanyNotInPortfolioError("não é da carteira")


NOW = datetime(2026, 11, 11, 13, 0, tzinfo=timezone.utc)  # quarta 10h em Brasília


@pytest.fixture
def env():
    db, access = FakeDb(), FakeAccess()
    clock = {"now": NOW}
    svc = EnrichmentService(db, access, client=httpx.AsyncClient(),
                            google_api_key="k", clock=lambda: clock["now"])
    return svc, db, access, clock


@respx.mock
async def test_servico_confere_acesso_antes_de_qualquer_chamada(env):
    svc, _, access, _ = env
    route = respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())

    access.in_portfolio = False
    with pytest.raises(CompanyNotInPortfolioError):
        await svc.get("u1", "g1", "07.175.725/0001-60", "receita")
    access.member, access.in_portfolio = False, True
    with pytest.raises(NotGroupMemberError):
        await svc.get("u1", "g1", CNPJ, "receita")
    assert route.call_count == 0
    with pytest.raises(ValueError):
        await svc.get("u1", "g1", CNPJ, "sei-la")


@respx.mock
async def test_servico_cacheia_dentro_da_validade_e_reconsulta_depois(env):
    svc, db, _, clock = env
    route = respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())

    a = await svc.get("u1", "g1", CNPJ, "receita")
    b = await svc.get("u1", "g1", CNPJ, "receita")
    assert route.call_count == 1
    assert a["status"] == b["status"] == "ok" and a["dados"]["razao_social"] == b["dados"]["razao_social"]
    assert a["origem"].startswith("Receita Federal")

    clock["now"] = NOW + timedelta(days=8)
    await svc.get("u1", "g1", CNPJ, "receita")
    assert route.call_count == 2


@respx.mock
async def test_servico_fonte_fora_devolve_o_ultimo_dado_marcado(env):
    svc, _, _, clock = env
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    await svc.get("u1", "g1", CNPJ, "receita")

    clock["now"] = NOW + timedelta(days=30)
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(500)
    respx.get(receita.MINHA_RECEITA_URL.format(cnpj=CNPJ)).respond(500)
    out = await svc.get("u1", "g1", CNPJ, "receita")
    assert out["status"] == "ok" and out["desatualizado"] is True

    # sem nada guardado: indisponível, sem erro HTTP
    respx.get(compras.RESULTADOS).respond(503)
    respx.get(compras.FORNECEDOR).respond(503)
    out = await svc.get("u1", "g1", CNPJ, "compras")
    assert out["status"] == "indisponivel" and out["dados"] is None and out["mensagem"]


@respx.mock
async def test_servico_vazio_tambem_fica_em_cache(env):
    svc, _, _, _ = env
    route = respx.post(regional.COMEX_URL).respond(200, json={"success": True, "data": {"list": []}})
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())

    a = await svc.get("u1", "g1", CNPJ, "comex")
    calls = route.call_count
    b = await svc.get("u1", "g1", CNPJ, "comex")
    assert a["status"] == b["status"] == "vazio"
    assert route.call_count == calls  # não reconsulta


@respx.mock
async def test_servico_regional_usa_o_municipio_da_receita_e_compartilha_por_cidade(env):
    svc, db, _, _ = env
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    respx.get(url__regex=r".*/agregados/6579/.*").respond(
        200, json=[{"resultados": [{"series": [{"serie": {"2025": "200000"}}]}]}])
    respx.get(url__regex=r".*/agregados/5938/.*").respond(
        200, json=[{"resultados": [{"series": [{"serie": {"2023": "1000"}}]}]}])

    out = await svc.get("u1", "g1", CNPJ, "municipio")

    assert out["status"] == "ok"
    # sem o nome do IBGE na resposta, monta a partir do endereço da Receita
    assert out["dados"]["municipio"] == "Jaragua do Sul (SC)"
    assert ("municipio", str(IBGE)) in db.cache  # chave = cidade, não CNPJ


PLACE = {
    "id": "PID1",
    "displayName": {"text": "WEG"},
    "rating": 4.7,
    "photos": [{"name": "places/PID1/photos/F1",
                "authorAttributions": [{"displayName": "Ana", "uri": "https://contrib/ana"}]}],
    "regularOpeningHours": {"periods": [
        {"open": {"day": 3, "hour": 7, "minute": 0}, "close": {"day": 3, "hour": 17, "minute": 0}}]},
}
PHOTO_MEDIA = "https://places.googleapis.com/v1/places/PID1/photos/F1/media"
DETAILS = "https://places.googleapis.com/v1/places/PID1"


@respx.mock
async def test_google_guarda_so_o_place_id_e_busca_o_resto_na_hora(env):
    svc, db, _, clock = env
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    search = respx.post(google_places.SEARCH_URL).respond(200, json={"places": [PLACE]})
    details = respx.get(DETAILS).respond(200, json={**PLACE, "rating": 4.8})
    media = respx.get(PHOTO_MEDIA).respond(
        200, json={"photoUri": "https://lh3.googleusercontent.com/foto"})

    a = await svc.get("u1", "g1", CNPJ, "google")

    # 1ª vez: busca por nome; guarda SÓ o place_id (termos do Google Maps)
    assert search.call_count == 1 and details.call_count == 0
    assert db.cache[("google_place_id", CNPJ)]["dados"] == {"place_id": "PID1"}
    assert ("google", CNPJ) not in db.cache
    assert a["status"] == "ok" and a["dados"]["nota"] == 4.7
    assert a["dados"]["foto"] == {"url": "https://lh3.googleusercontent.com/foto",
                                  "autor": "Ana", "autor_url": "https://contrib/ana"}
    assert "_foto" not in a["dados"]
    assert media.calls[0].request.url.params["skipHttpRedirect"] == "true"
    assert "key" not in media.calls[0].request.url.params  # chave só no cabeçalho
    assert a["dados"]["aberto_agora"] is True  # quarta 10h

    # depois: pelo place_id, conteúdo novo a cada vez (nada de conteúdo em cache)
    clock["now"] = NOW + timedelta(hours=10)  # quarta 20h
    b = await svc.get("u1", "g1", CNPJ, "google")
    assert search.call_count == 1 and details.call_count == 1
    assert b["dados"]["nota"] == 4.8 and b["dados"]["aberto_agora"] is False
    assert media.call_count == 2  # o link da foto também é pedido de novo


@respx.mock
async def test_google_place_id_que_deixou_de_existir_busca_de_novo(env):
    svc, db, _, _ = env
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    db.cache[("google_place_id", CNPJ)] = {"dados": {"place_id": "PID1"},
                                           "buscado_em": NOW.isoformat()}
    respx.get(DETAILS).respond(404)
    search = respx.post(google_places.SEARCH_URL).respond(
        200, json={"places": [{**PLACE, "id": "PID2", "photos": []}]})

    out = await svc.get("u1", "g1", CNPJ, "google")

    assert search.call_count == 1
    assert db.cache[("google_place_id", CNPJ)]["dados"] == {"place_id": "PID2"}
    assert out["status"] == "ok" and out["dados"]["foto"] is None


@respx.mock
async def test_google_sem_resultado_nao_repete_a_busca_paga_por_7_dias(env):
    svc, _, _, clock = env
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    search = respx.post(google_places.SEARCH_URL).respond(200, json={})

    assert (await svc.get("u1", "g1", CNPJ, "google"))["status"] == "vazio"
    assert (await svc.get("u1", "g1", CNPJ, "google"))["status"] == "vazio"
    assert search.call_count == 1
    clock["now"] = NOW + timedelta(days=8)
    await svc.get("u1", "g1", CNPJ, "google")
    assert search.call_count == 2


@respx.mock
async def test_google_foto_que_falha_nao_derruba_o_resto(env):
    svc, _, _, _ = env
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    respx.post(google_places.SEARCH_URL).respond(200, json={"places": [PLACE]})
    respx.get(PHOTO_MEDIA).respond(500)

    out = await svc.get("u1", "g1", CNPJ, "google")

    assert out["status"] == "ok" and out["dados"]["foto"] is None
    assert out["dados"]["nota"] == 4.7


@respx.mock
async def test_google_fora_do_ar_fica_indisponivel(env):
    svc, _, _, _ = env
    respx.get(receita.BRASILAPI_URL.format(cnpj=CNPJ)).respond(200, json=brasilapi_payload())
    respx.post(google_places.SEARCH_URL).respond(503)
    out = await svc.get("u1", "g1", CNPJ, "google")
    assert out["status"] == "indisponivel" and out["dados"] is None


async def test_servico_google_desligado_nao_chama_nada():
    svc = EnrichmentService(FakeDb(), FakeAccess(), client=httpx.AsyncClient(),
                            google_api_key="k", google_enabled=False)
    out = await svc.get("u1", "g1", CNPJ, "google")
    assert out["status"] == "desativado"
    svc = EnrichmentService(FakeDb(), FakeAccess(), client=httpx.AsyncClient(), google_api_key="")
    assert (await svc.get("u1", "g1", CNPJ, "google"))["status"] == "desativado"


# ─── Rota ───────────────────────────────────────────────────────────────


class FakeEnrichment:
    def __init__(self):
        self.calls, self.error = [], None

    async def get(self, uid, group_id, cnpj, fonte):
        self.calls.append((uid, group_id, cnpj, fonte))
        if self.error:
            raise self.error
        return {"fonte": fonte, "status": "ok"}


@pytest.fixture
def api(monkeypatch):
    fake = FakeEnrichment()
    monkeypatch.setattr(main, "enrichment_service", fake)
    return TestClient(main.app), fake


def _auth():
    return {"Authorization": f"Bearer {mint_internal_token('uid-1')['token']}"}


def test_rota_passa_identidade_e_fonte(api):
    client, fake = api
    r = client.get(f"/enriquecimento/compras?group_id=g1&cnpj={CNPJ}", headers=_auth())
    assert r.status_code == 200 and fake.calls == [("uid-1", "g1", CNPJ, "compras")]


def test_rota_erros(api):
    client, fake = api
    assert client.get(f"/enriquecimento/compras?group_id=g1&cnpj={CNPJ}").status_code == 422
    assert client.get(f"/enriquecimento/xpto?group_id=g1&cnpj={CNPJ}", headers=_auth()).status_code == 404
    fake.error = NotGroupMemberError("fora")
    assert client.get(f"/enriquecimento/receita?group_id=g1&cnpj={CNPJ}", headers=_auth()).status_code == 403
    fake.error = CompanyNotInPortfolioError("não")
    assert client.get(f"/enriquecimento/receita?group_id=g1&cnpj={CNPJ}", headers=_auth()).status_code == 404


@respx.mock
async def test_ibge_traz_o_nome_oficial_com_acento():
    serie = [{"resultados": [{"series": [{
        "localidade": {"id": "4208906", "nome": "Jaraguá do Sul (SC)"},
        "serie": {"2025": "200000"}}]}]}]
    respx.get(url__regex=r".*/agregados/.*").respond(200, json=serie)
    async with httpx.AsyncClient() as c:
        out = await regional.municipio(c, IBGE)
    assert out["nome_ibge"] == "Jaraguá do Sul (SC)"
