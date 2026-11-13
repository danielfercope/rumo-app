import io
import json
import zipfile
from datetime import date

import httpx
import pytest
import respx

from app.scripts.seed_agro import cli, enrich, hubspot, labeling, receita, relacionados
from app.scripts.seed_agro.enrich import Company


def make_zip(path, name, rows):
    text = "\n".join(";".join(f'"{c}"' for c in r) for r in rows)
    with zipfile.ZipFile(path, "w") as z:
        z.writestr(name, text.encode("latin-1"))


def est_row(base, cnae="4683400", *, matriz="1", situacao="02", uf="PR", mun="7535",
            inicio="20150310"):
    row = [""] * 30
    row[0], row[1], row[2] = base, "0001", "55"
    row[3], row[5], row[10], row[11], row[19], row[20] = matriz, situacao, inicio, cnae, uf, mun
    return row


# ─── Receita ────────────────────────────────────────────────────────────


def test_le_so_matriz_ativa_dos_cnaes_do_segmento(tmp_path):
    path = tmp_path / "E.zip"
    make_zip(path, "E.csv", [
        est_row("11111111"),                       # ok
        est_row("22222222", cnae="4711302"),       # outro CNAE
        est_row("33333333", matriz="2"),           # filial
        est_row("44444444", situacao="08"),        # baixada
        est_row("55555555", cnae="4623109", uf="RS"),
    ])

    found = receita.read_candidates(str(path))

    assert [c.cnpj for c in found] == ["11111111000155", "55555555000155"]
    assert found[0].uf == "PR" and found[0].ano == 2015
    assert found[1].cnae == "4623109"


def test_le_municipios(tmp_path):
    path = tmp_path / "M.zip"
    make_zip(path, "M.csv", [["7535", "JOINVILLE"], ["0001", "BRASILIA"]])
    assert receita.read_municipios(str(path)) == {"7535": "JOINVILLE", "0001": "BRASILIA"}


def test_faixas_de_abertura():
    assert [receita.decade(y) for y in (2024, 2015, 2003, 1990, None)] == [
        "2020+", "2010s", "2000s", "<2000", "?",
    ]


def _items():
    # população enviesada pra anos recentes, como nos arquivos baixados
    return (
        [("2020+", i) for i in range(700)]
        + [("2010s", i) for i in range(200)]
        + [("2000s", i) for i in range(60)]
        + [("<2000", i) for i in range(40)]
    )


def test_amostra_estratificada_compensa_o_vies_de_idade():
    sample = receita.stratified_sample(_items(), 100, key=lambda x: x[0], seed=1)

    counts = {k: sum(1 for s in sample if s[0] == k) for k in ("2020+", "2010s", "2000s", "<2000")}
    assert len(sample) == 100
    assert counts == {"2020+": 30, "2010s": 30, "2000s": 20, "<2000": 20}


def test_estrato_pequeno_entrega_tudo_e_a_sobra_vai_pros_outros():
    items = [("2020+", i) for i in range(500)] + [("<2000", i) for i in range(5)]
    sample = receita.stratified_sample(items, 100, key=lambda x: x[0], seed=1)
    assert len(sample) == 100  # não sai menor que o pedido
    assert sum(1 for s in sample if s[0] == "<2000") == 5


def test_amostra_e_reprodutivel_e_nunca_passa_do_total():
    a = receita.stratified_sample(_items(), 50, key=lambda x: x[0], seed=7)
    b = receita.stratified_sample(_items(), 50, key=lambda x: x[0], seed=7)
    c = receita.stratified_sample(_items(), 50, key=lambda x: x[0], seed=8)
    assert a == b and a != c
    assert len(receita.stratified_sample(_items()[:10], 50, key=lambda x: x[0])) == 10


# ─── Enriquecimento ─────────────────────────────────────────────────────


def raw(cnpj, **over):
    base = {
        "cnpj": cnpj, "razao_social": f"AGRO {cnpj} LTDA", "nome_fantasia": "AGRO",
        "porte": "DEMAIS", "natureza_juridica": "Sociedade Empresária Limitada",
        "codigo_natureza_juridica": 2062, "opcao_pelo_mei": False,
        "descricao_situacao_cadastral": "ATIVA", "uf": "PR", "municipio": "CASCAVEL",
        "cnae_fiscal_descricao": "Comércio atacadista de defensivos agrícolas",
        "data_inicio_atividade": "2012-05-01",
    }
    return {**base, **over}


@pytest.mark.parametrize("over, reason", [
    ({}, None),
    ({"descricao_situacao_cadastral": "BAIXADA"}, "inativa"),
    ({"codigo_natureza_juridica": 2135}, "empresario_individual"),
    ({"opcao_pelo_mei": True}, "mei"),
    ({"razao_social": ""}, "dados_incompletos"),
    ({"uf": None}, "dados_incompletos"),
    ({"uf": "EX"}, "exterior"),
])
def test_exclusoes(over, reason):
    assert enrich.exclusion_reason(raw("1", **over)) == reason


async def _no_sleep(_):
    pass


@respx.mock
async def test_enriquece_ate_juntar_o_pedido_e_conta_exclusoes():
    respx.get(f"{enrich.BASE_URL}/1").respond(200, json=raw("1"))
    respx.get(f"{enrich.BASE_URL}/2").respond(200, json=raw("2", opcao_pelo_mei=True))
    respx.get(f"{enrich.BASE_URL}/3").respond(404)
    respx.get(f"{enrich.BASE_URL}/4").respond(200, json=raw("4"))
    route5 = respx.get(f"{enrich.BASE_URL}/5").respond(200, json=raw("5"))

    accepted, excluded = await enrich.enrich(
        ["1", "2", "3", "4", "5"], 2, enrich.Cache(None), pause=0, sleep=_no_sleep
    )

    assert [c.cnpj for c in accepted] == ["1", "4"]
    assert excluded == {"mei": 1, "nao_encontrado": 1}
    assert not route5.called  # parou ao juntar o pedido


@respx.mock
async def test_cache_em_disco_evita_repetir_consultas(tmp_path):
    path = str(tmp_path / "cache.jsonl")
    route = respx.get(f"{enrich.BASE_URL}/1").respond(200, json=raw("1"))
    await enrich.enrich(["1"], 1, enrich.Cache(path), pause=0, sleep=_no_sleep)
    assert route.call_count == 1

    accepted, _ = await enrich.enrich(["1"], 1, enrich.Cache(path), pause=0, sleep=_no_sleep)

    assert route.call_count == 1 and [c.cnpj for c in accepted] == ["1"]


@respx.mock
async def test_limite_da_brasilapi_espera_e_tenta_de_novo():
    waits = []

    async def sleep(s):
        waits.append(s)

    respx.get(f"{enrich.BASE_URL}/1").mock(side_effect=[
        httpx.Response(429), httpx.Response(200, json=raw("1")),
    ])

    accepted, _ = await enrich.enrich(["1"], 1, enrich.Cache(None), pause=0, sleep=sleep)

    assert len(accepted) == 1 and waits and waits[0] >= 2


# ─── Regra sintética ────────────────────────────────────────────────────

UFS = ["SP", "PR", "MG", "RS", "MT", "GO", "SC", "BA", "MS", "PA"]


def companies(n=500):
    out = []
    for i in range(n):
        out.append(Company(
            cnpj=f"{i:014d}", razao_social=f"A{i}", nome_fantasia=None,
            porte=["MICRO EMPRESA", "EMPRESA DE PEQUENO PORTE", "DEMAIS"][i % 3],
            natureza_juridica="ltda", cnae_descricao="x", uf=UFS[i % len(UFS)],
            municipio="X", inicio_atividade=f"{2000 + (i * 7) % 25}-01-01",
        ))
    return out


TODAY = date(2026, 11, 8)


def test_taxa_de_clientes_fica_perto_da_meta():
    labeled = labeling.label(companies(), seed=1, today=TODAY)
    rate = sum(1 for x in labeled if x.status == "cliente") / len(labeled)
    assert 0.15 < rate < 0.25


def test_sul_converte_mais_que_o_resto():
    labeled = labeling.label(companies(1000), seed=1, today=TODAY)

    def rate(ufs):
        group = [x for x in labeled if x.company.uf in ufs]
        return sum(1 for x in group if x.status == "cliente") / len(group)

    assert rate(labeling.SUL) > 2 * rate({"BA", "PA", "MT", "GO"})


def test_regra_e_reprodutivel_e_o_ruido_impede_probabilidade_extrema():
    a = labeling.label(companies(), seed=3, today=TODAY)
    b = labeling.label(companies(), seed=3, today=TODAY)
    assert [x.status for x in a] == [x.status for x in b]
    assert all(0.02 < x.p_client < 0.98 for x in a)


def test_ha_perdidos_e_leads():
    statuses = {x.status for x in labeling.label(companies(), seed=1, today=TODAY)}
    assert statuses == {"cliente", "lead", "perdido"}


def test_estagio_a_tem_poucos_clientes_e_b_tem_todos():
    labeled = labeling.label(companies(), seed=1, today=TODAY)
    early = labeling.early_clients(labeled, 6)

    a = [labeling.status_at_stage(x, "A", early) for x in labeled]
    b = [labeling.status_at_stage(x, "B", early) for x in labeled]

    assert a.count("cliente") == 6
    assert b.count("cliente") == sum(1 for x in labeled if x.status == "cliente") > 6
    # os "perdidos" não mudam entre os estágios
    assert a.count("perdido") == b.count("perdido")


def test_teto_de_auc_e_alto_mas_nao_perfeito():
    labeled = labeling.label(companies(1000), seed=1, today=TODAY)
    assert 0.68 < labeling.ceiling_auc(labeled) < 0.88


def test_serializa_e_volta():
    labeled = labeling.label(companies(5), seed=1, today=TODAY)
    back = [labeling.Labeled.from_json(json.loads(json.dumps(x.to_json()))) for x in labeled]
    assert back == labeled


# ─── HubSpot ────────────────────────────────────────────────────────────

HS = hubspot.BASE_URL


def labeled_one(i=1, status="lead"):
    c = companies(i + 1)[i]
    return labeling.Labeled(c, 0.3, status)


def seeder():
    client = httpx.AsyncClient(base_url=HS, headers={"Authorization": "Bearer segredo-token"})
    return hubspot.HubSpotSeeder("segredo-token", client=client, sleep=_no_sleep, pause=0)


def test_so_vai_identificacao_da_empresa_nunca_telefone_ou_email():
    props = hubspot.company_properties(labeled_one(status="cliente"), "cliente", "L1")
    assert set(props) == {"name", "cnpj", "city", "state", "lifecyclestage", "rumo_seed_lote"}
    assert props["lifecyclestage"] == "customer" and props["rumo_seed_lote"] == "L1"
    assert props["cnpj"].isdigit()


def test_mapeia_status_para_o_ciclo_de_vida():
    assert hubspot.LIFECYCLE == {"cliente": "customer", "lead": "lead", "perdido": "other"}


@respx.mock
async def test_cria_so_as_propriedades_que_faltam():
    respx.get(f"{HS}/crm/v3/properties/companies/cnpj").respond(200, json={})
    respx.get(f"{HS}/crm/v3/properties/companies/rumo_seed_lote").respond(404)
    create = respx.post(f"{HS}/crm/v3/properties/companies").respond(201, json={})

    created = await seeder().ensure_properties()

    assert created == ["rumo_seed_lote"]
    body = json.loads(create.calls.last.request.content)
    assert body["name"] == "rumo_seed_lote" and body["type"] == "string"


def _search(results, after=None):
    body = {"results": results}
    if after:
        body["paging"] = {"next": {"after": after}}
    return httpx.Response(200, json=body)


@respx.mock
async def test_criar_pula_quem_ja_existe_no_lote_e_envia_em_lotes_de_100():
    payloads = [
        hubspot.company_properties(labeled_one(i), "lead", "L1") for i in range(1, 251)
    ]
    existing_cnpj = payloads[0]["cnpj"]
    respx.post(f"{HS}/crm/v3/objects/companies/search").mock(
        return_value=_search([{"id": "9", "properties": {"cnpj": existing_cnpj, "lifecyclestage": "lead"}}])
    )
    batch = respx.post(f"{HS}/crm/v3/objects/companies/batch/create").respond(201, json={})

    n = await seeder().create(payloads, "L1")

    assert n == 249 and batch.call_count == 3
    sizes = [len(json.loads(c.request.content)["inputs"]) for c in batch.calls]
    assert sizes == [100, 100, 49]


@respx.mock
async def test_busca_do_lote_pagina_e_filtra_pelo_marcador():
    search = respx.post(f"{HS}/crm/v3/objects/companies/search").mock(side_effect=[
        _search([{"id": "1", "properties": {"cnpj": "a", "lifecyclestage": "lead"}}], after="100"),
        _search([{"id": "2", "properties": {"cnpj": "b", "lifecyclestage": "customer"}}]),
    ])

    found = await seeder().existing("L1")

    assert found == {"a": {"id": "1", "lifecyclestage": "lead"},
                     "b": {"id": "2", "lifecyclestage": "customer"}}
    first = json.loads(search.calls[0].request.content)
    assert first["filterGroups"][0]["filters"][0] == {
        "propertyName": "rumo_seed_lote", "operator": "EQ", "value": "L1"}
    assert json.loads(search.calls[1].request.content)["after"] == "100"


@respx.mock
async def test_promover_atualiza_so_quem_mudou_de_estagio():
    respx.post(f"{HS}/crm/v3/objects/companies/search").mock(return_value=_search([
        {"id": "1", "properties": {"cnpj": "a", "lifecyclestage": "lead"}},
        {"id": "2", "properties": {"cnpj": "b", "lifecyclestage": "customer"}},
        {"id": "3", "properties": {"cnpj": "c", "lifecyclestage": "lead"}},
    ]))
    update = respx.post(f"{HS}/crm/v3/objects/companies/batch/update").respond(200, json={})

    n = await seeder().set_status("L1", {"a": "cliente", "b": "cliente", "c": "lead", "zz": "cliente"})

    assert n == 1  # só "a": b já é cliente, c continua lead, zz não existe no lote
    assert json.loads(update.calls.last.request.content)["inputs"] == [
        {"id": "1", "properties": {"lifecyclestage": "customer"}}]


@respx.mock
async def test_limpar_arquiva_so_o_que_e_do_lote():
    respx.post(f"{HS}/crm/v3/objects/companies/search").mock(return_value=_search([
        {"id": "1", "properties": {"cnpj": "a"}}, {"id": "2", "properties": {"cnpj": "b"}}]))
    archive = respx.post(f"{HS}/crm/v3/objects/companies/batch/archive").respond(204)

    assert await seeder().delete_lote("L1") == 2
    assert json.loads(archive.calls.last.request.content)["inputs"] == [{"id": "1"}, {"id": "2"}]


@respx.mock
async def test_token_recusado_nao_vaza_o_token_na_mensagem():
    respx.post(f"{HS}/crm/v3/objects/companies/search").respond(401, text="nope")
    with pytest.raises(hubspot.HubSpotError) as exc:
        await seeder().existing("L1")
    assert "segredo-token" not in str(exc.value) and "escopo de escrita" in str(exc.value)


@respx.mock
async def test_limite_de_requisicoes_do_hubspot_respeita_retry_after():
    waits = []

    async def sleep(s):
        waits.append(s)

    respx.post(f"{HS}/crm/v3/objects/companies/search").mock(side_effect=[
        httpx.Response(429, headers={"Retry-After": "3"}), _search([])])
    client = httpx.AsyncClient(base_url=HS)
    s = hubspot.HubSpotSeeder("t", client=client, sleep=sleep, pause=0)

    assert await s.existing("L1") == {}
    assert waits[0] == 3.0


# ─── CLI ────────────────────────────────────────────────────────────────


def _labeled_file(tmp_path):
    path = tmp_path / "labeled.json"
    labeled = labeling.label(companies(60), seed=1, today=TODAY)
    path.write_text(json.dumps([x.to_json() for x in labeled]))
    return str(path)


@respx.mock
async def test_upload_sem_apply_e_dry_run_e_nao_faz_nenhuma_requisicao(tmp_path, capsys, monkeypatch):
    monkeypatch.delenv("HUBSPOT_SEED_TOKEN", raising=False)  # nem token é preciso
    args = cli.build_parser().parse_args(["upload", "--in", _labeled_file(tmp_path), "--stage", "A", "--limit", "5"])

    assert await cli.cmd_upload(args) == 0

    out = capsys.readouterr().out
    assert "DRY-RUN" in out and "5 empresas" in out
    assert len(respx.calls) == 0


async def test_upload_com_apply_exige_o_token(tmp_path, monkeypatch):
    monkeypatch.delenv("HUBSPOT_SEED_TOKEN", raising=False)
    args = cli.build_parser().parse_args(["upload", "--in", _labeled_file(tmp_path), "--apply"])
    with pytest.raises(SystemExit):
        await cli.cmd_upload(args)


async def test_promote_e_clean_tambem_sao_dry_run_por_padrao(tmp_path, capsys):
    f = _labeled_file(tmp_path)
    p = cli.build_parser()
    assert await cli.cmd_promote(p.parse_args(["promote", "--in", f])) == 0
    assert await cli.cmd_clean(p.parse_args(["clean"])) == 0
    assert capsys.readouterr().out.count("DRY-RUN") == 2


def test_label_imprime_status_e_teto(tmp_path, capsys):
    inp = tmp_path / "in.json"
    inp.write_text(json.dumps([c.to_json() for c in companies(200)]))
    out = tmp_path / "out.json"

    cli.cmd_label(cli.build_parser().parse_args(["label", "--in", str(inp), "--out", str(out)]))

    text = capsys.readouterr().out
    assert "Teto de AUC" in text and "Estágio A: 6 clientes" in text
    assert len(json.loads(out.read_text())) == 200


def test_label_aceita_taxa_de_clientes_maior(tmp_path):
    inp = tmp_path / "in.json"
    inp.write_text(json.dumps([c.to_json() for c in companies(400)]))

    def clientes(*extra):
        out = tmp_path / "out.json"
        cli.cmd_label(cli.build_parser().parse_args(
            ["label", "--in", str(inp), "--out", str(out), *extra]))
        return sum(x["status"] == "cliente" for x in json.loads(out.read_text()))

    # 30% esperado: a taxa sorteada fica perto disso e acima da padrão (20%)
    n = clientes("--client-rate", "0.30")
    assert 0.24 <= n / 400 <= 0.36
    assert n > clientes()


# ─── Contatos e negócios fictícios ──────────────────────────────────────


def test_contato_ficticio_nao_tem_telefone_e_usa_dominio_reservado():
    props = relacionados.contact_properties(companies(1)[0])
    assert set(props) == {"firstname", "lastname", "email", "jobtitle"}
    assert props["email"].endswith("@seed.example.com")
    assert relacionados.is_seed_contact(props)
    assert not relacionados.is_seed_contact({"email": "joao@empresa.com.br"})


def test_contato_e_deterministico_e_o_email_e_unico_por_empresa():
    cs = companies(60)
    emails = [relacionados.contact_properties(c)["email"] for c in cs]
    assert emails == [relacionados.contact_properties(c)["email"] for c in cs]
    assert len(set(emails)) == len(cs)


def test_negocio_acompanha_o_status_e_leva_o_marcador_do_lote():
    c = companies(1)[0]
    assert relacionados.deal_properties(c, "cliente", "L1")["dealstage"] == "closedwon"
    assert relacionados.deal_properties(c, "perdido", "L1")["dealstage"] == "closedlost"
    open_deal = relacionados.deal_properties(c, "lead", "L1")
    assert open_deal["dealstage"] in relacionados.OPEN_STAGES
    assert open_deal["dealname"].startswith("[L1] ")
    assert relacionados.is_seed_deal(open_deal, "L1")
    assert not relacionados.is_seed_deal(open_deal, "outro-lote")
    assert int(open_deal["amount"]) % 5000 == 0


def _mock_associations(contacts_by_company=None, deals_by_company=None):
    def reply(links):
        def handler(request):
            ids = [i["id"] for i in json.loads(request.content)["inputs"]]
            return httpx.Response(200, json={"results": [
                {"from": {"id": i}, "to": [{"toObjectId": int(t)} for t in links.get(i, [])]}
                for i in ids if links.get(i)
            ]})
        return handler

    respx.post(f"{HS}/crm/v4/associations/companies/contacts/batch/read").mock(
        side_effect=reply(contacts_by_company or {}))
    respx.post(f"{HS}/crm/v4/associations/companies/deals/batch/read").mock(
        side_effect=reply(deals_by_company or {}))


def _mock_read_objects(contacts=None, deals=None):
    def reply(rows):
        def handler(request):
            ids = [i["id"] for i in json.loads(request.content)["inputs"]]
            return httpx.Response(200, json={"results": [
                {"id": i, "properties": rows[i]} for i in ids if i in rows]})
        return handler

    respx.post(f"{HS}/crm/v3/objects/contacts/batch/read").mock(side_effect=reply(contacts or {}))
    respx.post(f"{HS}/crm/v3/objects/deals/batch/read").mock(side_effect=reply(deals or {}))


def _related_items(n=2):
    return [
        (str(100 + i), relacionados.contact_properties(c),
         relacionados.deal_properties(c, "lead", "L1"))
        for i, c in enumerate(companies(n))
    ]


@respx.mock
async def test_cria_contato_e_negocio_e_associa_os_tres():
    items = _related_items()
    _mock_associations()
    _mock_read_objects()
    # o HubSpot devolve ids novos; a ordem da resposta não é garantida
    contacts = respx.post(f"{HS}/crm/v3/objects/contacts/batch/create").mock(
        return_value=httpx.Response(201, json={"results": [
            {"id": "901", "properties": {"email": items[1][1]["email"].upper()}},
            {"id": "900", "properties": {"email": items[0][1]["email"]}},
        ]}))
    deals = respx.post(f"{HS}/crm/v3/objects/deals/batch/create").respond(201, json={})

    n_contacts, n_deals = await seeder().create_related("L1", items)

    assert (n_contacts, n_deals) == (2, 2)
    sent_contacts = json.loads(contacts.calls.last.request.content)["inputs"]
    assert sent_contacts[0]["associations"][0]["to"] == {"id": "100"}
    assert sent_contacts[0]["associations"][0]["types"][0]["associationTypeId"] == 1
    sent_deals = json.loads(deals.calls.last.request.content)["inputs"]
    for deal, (company_id, contact_id) in zip(sent_deals, (("100", "900"), ("101", "901"))):
        links = {a["types"][0]["associationTypeId"]: a["to"]["id"] for a in deal["associations"]}
        assert links == {5: company_id, 3: contact_id}  # empresa e o contato certo


@respx.mock
async def test_e_idempotente_preserva_o_que_ja_e_do_lote_e_ignora_o_que_nao_e():
    items = _related_items()
    # empresa 100 já tem contato e negócio do lote; a 101 só tem um contato REAL
    _mock_associations({"100": ["900"], "101": ["950"]}, {"100": ["800"]})
    _mock_read_objects(
        contacts={"900": {"email": items[0][1]["email"]}, "950": {"email": "gente.real@empresa.com.br"}},
        deals={"800": {"dealname": "[L1] qualquer"}},
    )
    contacts = respx.post(f"{HS}/crm/v3/objects/contacts/batch/create").mock(
        return_value=httpx.Response(201, json={"results": [
            {"id": "901", "properties": {"email": items[1][1]["email"]}}]}))
    deals = respx.post(f"{HS}/crm/v3/objects/deals/batch/create").respond(201, json={})

    n_contacts, n_deals = await seeder().create_related("L1", items)

    assert (n_contacts, n_deals) == (1, 1)
    assert len(json.loads(contacts.calls.last.request.content)["inputs"]) == 1
    only = json.loads(deals.calls.last.request.content)["inputs"][0]
    assert {a["to"]["id"] for a in only["associations"]} == {"101", "901"}


@respx.mock
async def test_apagar_so_arquiva_contatos_e_negocios_do_lote():
    respx.post(f"{HS}/crm/v3/objects/companies/search").mock(
        return_value=_search([{"id": "100", "properties": {"cnpj": "1", "lifecyclestage": "lead"}}]))
    _mock_associations({"100": ["900", "950"]}, {"100": ["800", "801"]})
    _mock_read_objects(
        contacts={"900": {"email": "a.b.1@seed.example.com"}, "950": {"email": "real@empresa.com.br"}},
        deals={"800": {"dealname": "[L1] seed"}, "801": {"dealname": "negócio real"}},
    )
    order = []
    archive = {}
    for kind in ("deals", "contacts"):
        def handler(request, kind=kind):
            order.append(kind)
            archive[kind] = [i["id"] for i in json.loads(request.content)["inputs"]]
            return httpx.Response(204)
        respx.post(f"{HS}/crm/v3/objects/{kind}/batch/archive").mock(side_effect=handler)

    assert await seeder().delete_related("L1") == (1, 1)

    assert archive == {"deals": ["800"], "contacts": ["900"]}  # o real fica intacto
    assert order == ["deals", "contacts"]


@respx.mock
async def test_relate_sem_apply_e_dry_run_e_nao_faz_requisicao(tmp_path, capsys, monkeypatch):
    monkeypatch.delenv("HUBSPOT_SEED_TOKEN", raising=False)
    args = cli.build_parser().parse_args(["relate", "--in", _labeled_file(tmp_path), "--limit", "3"])

    assert await cli.cmd_relate(args) == 0

    out = capsys.readouterr().out
    assert "DRY-RUN" in out and "3 contatos + 3 negócios" in out
    assert len(respx.calls) == 0


# ─── rebalance: leva a carteira que já está no CRM a N% de clientes ─────


def _carteira(n_clientes, n_leads, n_perdidos=0):
    found = {}
    for i in range(n_clientes + n_leads + n_perdidos):
        stage = "customer" if i < n_clientes else "lead" if i < n_clientes + n_leads else "other"
        found[f"cnpj{i}"] = {"id": str(i), "lifecyclestage": stage}
    return found


def test_rebalance_conta_clientes_existentes_e_nunca_promove_perdidos():
    found = _carteira(n_clientes=5, n_leads=90, n_perdidos=5)  # 100 empresas

    picked = cli.pick_promotions(found, 0.30, seed=1)

    assert len(picked) == 25  # 30 alvo − 5 que já são clientes
    assert all(found[v["cnpj"]]["lifecyclestage"] == "lead" for v in picked.values())
    assert picked == cli.pick_promotions(found, 0.30, seed=1)  # reprodutível


def test_rebalance_nao_faz_nada_se_ja_atingiu_a_taxa():
    assert cli.pick_promotions(_carteira(40, 60), 0.30, seed=1) == {}


@respx.mock
async def test_rebalance_dry_run_so_le_e_apply_grava_registro_e_desfaz(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("HUBSPOT_SEED_TOKEN", "segredo-token")
    rows = [{"id": str(i), "properties": {"cnpj": f"c{i}", "lifecyclestage": "lead"}} for i in range(10)]
    respx.post(f"{HS}/crm/v3/objects/companies/search").mock(return_value=_search(rows))
    update = respx.post(f"{HS}/crm/v3/objects/companies/batch/update").respond(200, json={})
    out = tmp_path / "alt.json"
    p = cli.build_parser()

    await cli.cmd_rebalance(p.parse_args(["rebalance", "--out", str(out)]))
    assert update.call_count == 0 and "DRY-RUN" in capsys.readouterr().out

    await cli.cmd_rebalance(p.parse_args(["rebalance", "--out", str(out), "--apply"]))
    sent = json.loads(update.calls[0].request.content)["inputs"]
    assert len(sent) == 3 and all(x["properties"] == {"lifecyclestage": "customer"} for x in sent)
    assert len(json.loads(out.read_text())) == 3

    await cli.cmd_rebalance(p.parse_args(["rebalance", "--desfazer", str(out), "--apply"]))
    undone = json.loads(update.calls[1].request.content)["inputs"]
    assert len(undone) == 3 and all(x["properties"] == {"lifecyclestage": "lead"} for x in undone)
    # sem --lote a busca é por CNPJ preenchido, não pelo marcador do seed
    first = json.loads(respx.calls[0].request.content)
    assert first["filterGroups"][0]["filters"][0]["operator"] == "HAS_PROPERTY"
