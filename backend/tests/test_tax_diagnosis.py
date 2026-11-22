from datetime import date, datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app import main
from app.errors import CompanyNotInPortfolioError, CrmNotAvailableError, NotGroupMemberError
from app.internal_token import mint_internal_token
from app.services.enrichment import receita as receita_source
from app.services.tax_diagnosis.catalog import (
    CatalogRepository,
    Catalogo,
    CatalogUnavailable,
)
from app.services.tax_diagnosis.rules import REGRAS, diagnose
from app.services.tax_diagnosis.service import TaxDiagnosisService
from app.services.tax_diagnosis.signals import PRESUMIDO, REAL, SIMPLES, extract

from .test_enrichment import CNPJ, brasilapi_payload

HOJE = date(2026, 11, 20)  # janela 2022–2026


def tese_row(tese_id, *, em_discussao=False, cnaes=(), perguntas=("Pergunta?",),
             atualizado_em="2026-11-01T00:00:00+00:00"):
    """Uma linha de `teses_tributarias` como o PostgREST devolve (com embeds)."""
    return {
        "id": tese_id,
        "titulo": f"Tese {tese_id}",
        "resumo": "Resumo.",
        "tributos": ["PIS", "COFINS"],
        "base_legal": "Lei X",
        "situacao_juridica": "Pacificada",
        "em_discussao": em_discussao,
        "como_abordar": "Abordagem.",
        "atualizado_em": atualizado_em,
        "teses_tributarias_perguntas": [
            {"ordem": i, "texto": t, "atualizado_em": atualizado_em}
            for i, t in reversed(list(enumerate(perguntas, 1)))
        ],
        "teses_tributarias_cnaes": [
            {"cnae": c, "descricao": d, "parcial": parcial, "atualizado_em": atualizado_em}
            for c, d, parcial in cnaes
        ],
    }


# Recorte do conteúdo de db/schema/020_teses_tributarias.sql com o que os testes usam.
ROWS = [
    tese_row("monofasico_simples", cnaes=[
        ("4771701", "medicamentos", False),
        ("4723700", "bebidas", False),
        ("4711302", "supermercado (bebidas, higiene e cosméticos)", True),
    ]),
    tese_row("icms_st_simples", cnaes=[
        ("4744005", "materiais de construção", False),
        ("4771701", "medicamentos", False),
        ("4711302", "supermercado", False),
    ]),
    tese_row("icms_base_pis_cofins"),
    tese_row("insumos_lucro_real"),
    tese_row("retencoes_orgaos_publicos"),
    tese_row("iss_base_pis_cofins", em_discussao=True),
    tese_row("verbas_indenizatorias"),
]
CAT = Catalogo.from_rows(ROWS)


def cadastro(**over) -> dict:
    """Receita normalizada (o `dados` da fonte), a partir do payload da BrasilAPI."""
    return receita_source.normalize(brasilapi_payload(**over))


def farmacia_simples(**over) -> dict:
    base = dict(
        cnae_fiscal=4771701,
        cnae_fiscal_descricao="Comércio varejista de produtos farmacêuticos",
        cnaes_secundarios=[],
        opcao_pelo_simples=True,
        data_opcao_pelo_simples="2015-01-01",
        regime_tributario=[],
        porte="EMPRESA DE PEQUENO PORTE",
    )
    base.update(over)
    return cadastro(**base)


def industria(regime: str, anos=range(2020, 2026), **over) -> dict:
    base = dict(
        cnae_fiscal=2710401,
        cnae_fiscal_descricao="Fabricação de geradores",
        regime_tributario=[{"ano": a, "forma_de_tributacao": regime} for a in anos],
    )
    base.update(over)
    return cadastro(**base)


def compras(recente=0.0, anterior=0.0, orgaos=0) -> dict:
    return {
        "ultimos_12_meses": {"valor": recente, "orgaos": orgaos},
        "12_meses_anteriores": {"valor": anterior},
    }


def run(receita: dict, comp: dict | None = None, cat: Catalogo = CAT) -> dict:
    return diagnose(extract(receita, comp, HOJE), cat)


def ids(result: dict) -> list[str]:
    out = [result["principal"]["id"]] if result["principal"] else []
    return out + [o["id"] for o in result["outras"]]


# ─── Sinais ─────────────────────────────────────────────────────────────


def test_sinais_janela_de_5_anos_e_simples_pelas_datas():
    s = extract(industria("LUCRO PRESUMIDO", anos=range(2018, 2026)), None, HOJE)
    assert s.anos(PRESUMIDO) == [2022, 2023, 2024, 2025]  # 2018–2021 fora

    s = extract(farmacia_simples(), None, HOJE)
    assert s.anos(SIMPLES) == [2022, 2023, 2024, 2025, 2026]
    assert s.cnae_principal == "4771701"


def test_sinais_exclusao_do_simples_e_historico_declarado():
    rec = cadastro(
        opcao_pelo_simples=False,
        data_opcao_pelo_simples="2010-01-01",
        data_exclusao_do_simples="2024-01-01",
        regime_tributario=[{"ano": 2024, "forma_de_tributacao": "LUCRO PRESUMIDO"},
                           {"ano": 2025, "forma_de_tributacao": "LUCRO PRESUMIDO"}],
    )
    s = extract(rec, None, HOJE)
    assert s.anos(SIMPLES) == [2022, 2023]  # excluído em 1º de janeiro: 2024 já é fora
    assert s.anos(PRESUMIDO) == [2024, 2025]
    assert s.mudancas_de_regime == [(2024, SIMPLES, PRESUMIDO)]


def test_sinais_compras_sem_fonte_e_sem_vendas():
    assert extract(cadastro(), None, HOJE).compras_recente is None
    assert extract(cadastro(), {}, HOJE).compras_total == 0


# ─── Teses ──────────────────────────────────────────────────────────────


def test_monofasico_pelo_cnae_principal_e_alta_e_vence_o_icms_st():
    r = run(farmacia_simples())
    assert r["principal"]["id"] == "monofasico_simples"
    assert r["principal"]["confianca"] == "alta"
    assert r["principal"]["periodo"] == "2022–2026"
    assert "icms_st_simples" in ids(r)
    textos = " ".join(e["texto"] for e in r["principal"]["evidencias"])
    assert "47.71-7/01" in textos and "medicamentos" in textos


def test_monofasico_pelo_cnae_secundario_e_media():
    r = run(farmacia_simples(
        cnae_fiscal=5611201, cnae_fiscal_descricao="Restaurantes",
        cnaes_secundarios=[{"codigo": 4723700, "descricao": "Bebidas"}]))
    achado = next(a for a in [r["principal"], *r["outras"]] if a["id"] == "monofasico_simples")
    assert achado["confianca"] == "media"


def test_supermercado_e_monofasico_parcial():
    r = run(farmacia_simples(cnae_fiscal=4711302, cnae_fiscal_descricao="Supermercados"))
    assert r["principal"]["id"] == "monofasico_simples"
    assert r["principal"]["confianca"] == "media"


def test_sem_simples_nao_tem_monofasico_nem_icms_st():
    r = run(farmacia_simples(opcao_pelo_simples=False, data_opcao_pelo_simples=None,
                             regime_tributario=[{"ano": 2025, "forma_de_tributacao": "LUCRO PRESUMIDO"}]))
    assert "monofasico_simples" not in ids(r) and "icms_st_simples" not in ids(r)
    assert r["principal"]["id"] == "icms_base_pis_cofins"  # comércio no Presumido


def test_icms_st_para_comercio_de_material_de_construcao():
    r = run(farmacia_simples(cnae_fiscal=4744005, cnae_fiscal_descricao="Materiais de construção"))
    assert ids(r) == ["icms_st_simples"]


def test_industria_no_presumido_tem_tese_69_e_nao_insumos():
    r = run(industria("LUCRO PRESUMIDO"))
    assert r["principal"]["id"] == "icms_base_pis_cofins"
    assert "insumos_lucro_real" not in ids(r)


def test_industria_no_lucro_real_tem_tese_69_e_insumos():
    r = run(industria("LUCRO REAL"))
    assert {"icms_base_pis_cofins", "insumos_lucro_real"} <= set(ids(r))


def test_regime_so_fora_da_janela_nao_conta():
    r = run(industria("LUCRO REAL", anos=range(2015, 2021), porte="EMPRESA DE PEQUENO PORTE"))
    assert r["principal"] is None and r["outras"] == []


def test_retencoes_dependem_de_vender_ao_governo_e_do_valor():
    rec = industria("LUCRO PRESUMIDO", porte="EMPRESA DE PEQUENO PORTE")
    assert "retencoes_orgaos_publicos" not in ids(run(rec, compras()))
    assert "retencoes_orgaos_publicos" not in ids(run(rec, None))

    baixa = next(a for a in run(rec, compras(10_000))["outras"] if a["id"] == "retencoes_orgaos_publicos")
    assert baixa["confianca"] == "baixa"
    r = run(rec, compras(400_000, 300_000, orgaos=3))
    media = next(a for a in [r["principal"], *r["outras"]] if a["id"] == "retencoes_orgaos_publicos")
    assert media["confianca"] == "media"
    assert media["evidencias"][0]["fonte"] == "Compras públicas (PNCP)"
    assert "R$ 700 mil" in media["evidencias"][0]["texto"]


def test_simples_nao_tem_retencoes():
    assert "retencoes_orgaos_publicos" not in ids(run(farmacia_simples(), compras(900_000)))


def test_iss_so_e_principal_sem_outra_tese():
    servico = industria("LUCRO PRESUMIDO", cnae_fiscal=6201501,
                        cnae_fiscal_descricao="Desenvolvimento de software",
                        porte="EMPRESA DE PEQUENO PORTE")
    r = run(servico)
    assert r["principal"]["id"] == "iss_base_pis_cofins"
    assert r["principal"]["confianca"] == "baixa"

    r = run(servico, compras(10_000))  # retenção baixa vence a tese em discussão
    assert r["principal"]["id"] == "retencoes_orgaos_publicos"
    assert ids(r)[-1] == "iss_base_pis_cofins"


def test_verbas_indenizatorias_para_porte_demais_fora_do_simples():
    assert "verbas_indenizatorias" in ids(run(industria("LUCRO REAL", porte="DEMAIS")))
    assert "verbas_indenizatorias" not in ids(
        run(industria("LUCRO REAL", porte="EMPRESA DE PEQUENO PORTE")))


def test_mudanca_de_regime_reforca_e_vira_evidencia():
    sem = run(industria("LUCRO PRESUMIDO", anos=range(2022, 2026)))
    com_rec = industria("LUCRO PRESUMIDO", anos=range(2024, 2026),
                        opcao_pelo_simples=False, data_opcao_pelo_simples="2010-01-01",
                        data_exclusao_do_simples="2024-01-01")
    com = run(com_rec)
    assert com["principal"]["id"] == "icms_base_pis_cofins"
    assert any("Mudou de Simples Nacional para Lucro Presumido em 2024" in e["texto"]
               for e in com["principal"]["evidencias"])
    assert not any("Mudou" in e["texto"] for e in sem["principal"]["evidencias"])


# ─── Catálogo (banco) ───────────────────────────────────────────────────


def test_catalogo_monta_teses_perguntas_em_ordem_cnaes_e_versao():
    rows = [tese_row("monofasico_simples", perguntas=("Primeira?", "Segunda?"),
                     cnaes=[("4771701", "medicamentos", False)]),
            tese_row("verbas_indenizatorias", atualizado_em="2026-11-15T00:00:00+00:00")]
    cat = Catalogo.from_rows(rows)
    t = cat.get("monofasico_simples")
    assert t.perguntas == ("Primeira?", "Segunda?")
    assert t.cnaes["4771701"].descricao == "medicamentos" and not t.cnaes["4771701"].parcial
    assert cat.versao == "2026-11-15T00:00:00+00:00"


def test_toda_regra_tem_tese_no_conteudo_inicial_do_banco():
    """As regras e o INSERT da 020 usam os mesmos ids."""
    from pathlib import Path
    sql = (Path(__file__).parents[2] / "db/schema/020_teses_tributarias.sql").read_text()
    for tese_id in REGRAS:
        assert f"('{tese_id}'," in sql, tese_id


def test_texto_e_perguntas_vem_do_banco():
    r = run(farmacia_simples())
    assert r["principal"]["titulo"] == "Tese monofasico_simples"
    assert r["principal"]["perguntas"] == ["Pergunta?"]


def test_tese_desativada_ou_fora_do_catalogo_nao_aparece():
    sem_mono = Catalogo.from_rows([r for r in ROWS if r["id"] != "monofasico_simples"])
    r = run(farmacia_simples(), cat=sem_mono)
    assert "monofasico_simples" not in ids(r) and r["principal"]["id"] == "icms_st_simples"


def test_cnae_novo_no_banco_passa_a_disparar_a_tese():
    rec = farmacia_simples(cnae_fiscal=4789099, cnae_fiscal_descricao="Outros produtos")
    assert run(rec)["principal"] is None
    rows = [r for r in ROWS if r["id"] != "monofasico_simples"] + [
        tese_row("monofasico_simples", cnaes=[("4789099", "produtos de higiene", False)])]
    assert run(rec, cat=Catalogo.from_rows(rows))["principal"]["id"] == "monofasico_simples"


class FakeDb:
    def __init__(self, rows):
        self.rows, self.calls, self.error = rows, [], None

    async def select(self, table, params):
        self.calls.append((table, params))
        if self.error:
            raise self.error
        return self.rows


async def test_repositorio_le_so_ativas_guarda_em_memoria_e_sobrevive_a_queda():
    db = FakeDb(ROWS)
    now = {"t": datetime(2026, 11, 20, tzinfo=timezone.utc)}
    repo = CatalogRepository(db, clock=lambda: now["t"])

    cat = await repo.get()
    assert set(cat.teses) == set(REGRAS)
    table, params = db.calls[0]
    assert table == "teses_tributarias" and params["ativa"] == "eq.true"
    assert "teses_tributarias_perguntas(" in params["select"]

    await repo.get()
    assert len(db.calls) == 1  # dentro da validade não relê

    now["t"] += timedelta(minutes=6)
    db.error = RuntimeError("banco fora")
    assert (await repo.get()) is cat  # fora do ar: última cópia
    assert len(db.calls) == 2


async def test_repositorio_sem_copia_e_banco_fora_levanta():
    db = FakeDb(ROWS)
    db.error = RuntimeError("banco fora")
    with pytest.raises(CatalogUnavailable):
        await CatalogRepository(db).get()


# ─── Bloqueios ──────────────────────────────────────────────────────────


def test_empresa_inapta_e_bloqueada():
    r = run(farmacia_simples(descricao_situacao_cadastral="INAPTA"))
    assert r["principal"] is None and "inapta" in r["bloqueio"]["motivo"]


def test_mei_e_bloqueado():
    r = run(farmacia_simples(opcao_pelo_mei=True))
    assert r["principal"] is None and "MEI" in r["bloqueio"]["motivo"]


def test_imune_descarta_teses_de_pis_cofins_e_irpj():
    r = run(industria("LUCRO REAL", anos=[2024]))
    assert "icms_base_pis_cofins" in ids(r)
    imune = industria("LUCRO REAL", anos=[2024])
    imune["regime_tributario"].insert(0, {"ano": 2025, "forma": "IMUNE DO IRPJ"})
    r = run(imune)
    assert not {"icms_base_pis_cofins", "insumos_lucro_real", "iss_base_pis_cofins"} & set(ids(r))


# ─── Serviço ────────────────────────────────────────────────────────────


class FakeAccess:
    def __init__(self):
        self.error, self.calls = None, []

    async def _check(self, *args):
        self.calls.append(args)
        if self.error:
            raise self.error

    async def require_member(self, uid, group_id):
        await self._check("member", uid, group_id)

    async def require_crm(self, group_id):
        await self._check("crm", group_id)

    async def require_cnpj_in_portfolio(self, group_id, cnpj):
        await self._check("portfolio", group_id, cnpj)


class FakeCatalog:
    def __init__(self, cat=CAT, error=None):
        self.cat, self.error = cat, error

    async def get(self):
        if self.error:
            raise self.error
        return self.cat


class FakeEnrichment:
    def __init__(self, receita, compras):
        self.envs = {"receita": receita, "compras": compras}
        self.calls = []

    async def fetch_cached(self, fonte, cnpj):
        self.calls.append((fonte, cnpj))
        env = self.envs[fonte]
        if isinstance(env, Exception):
            raise env
        return env


def env(status="ok", dados=None, atualizado_em="2026-11-20T10:00:00+00:00"):
    return {"status": status, "dados": dados, "atualizado_em": atualizado_em}


def service(receita, compras, catalog=None):
    access = FakeAccess()
    enr = FakeEnrichment(receita, compras)
    svc = TaxDiagnosisService(access, enr, catalog or FakeCatalog(), today=lambda: HOJE)
    return svc, access, enr


async def test_servico_confere_acesso_antes_de_ler_as_fontes():
    svc, access, enr = service(env(dados=farmacia_simples()), env(dados=compras()))
    access.error = CompanyNotInPortfolioError("não")
    with pytest.raises(CompanyNotInPortfolioError):
        await svc.get("u1", "g1", CNPJ)
    assert enr.calls == []


async def test_servico_monta_o_diagnostico():
    svc, access, enr = service(env(dados=farmacia_simples()), env(status="vazio"))
    r = await svc.get("u1", "g1", "07.175.725/0001-60")
    assert r["status"] == "ok" and r["principal"]["id"] == "monofasico_simples"
    assert r["fontes_faltando"] == [] and r["aviso"]
    assert r["versao"] == "2026-11-01T00:00:00+00:00"
    assert sorted(enr.calls) == [("compras", CNPJ), ("receita", CNPJ)]
    assert [c[0] for c in access.calls] == ["member", "crm", "portfolio"]


async def test_servico_sem_compras_segue_sem_a_tese_de_retencoes():
    svc, *_ = service(env(dados=industria("LUCRO REAL")), env(status="indisponivel"))
    r = await svc.get("u1", "g1", CNPJ)
    assert r["status"] == "ok" and r["fontes_faltando"] == ["compras"]
    assert "retencoes_orgaos_publicos" not in ids(r)

    svc, *_ = service(env(dados=industria("LUCRO REAL")), RuntimeError("bug"))
    assert (await svc.get("u1", "g1", CNPJ))["fontes_faltando"] == ["compras"]


async def test_servico_sem_receita_nao_diagnostica():
    for receita, status in (
        (env(status="vazio"), "vazio"),
        (env(status="indisponivel"), "indisponivel"),
        (RuntimeError("bug"), "indisponivel"),
    ):
        svc, *_ = service(receita, env(dados=compras()))
        r = await svc.get("u1", "g1", CNPJ)
        assert r["status"] == status and r["principal"] is None


async def test_servico_sem_catalogo_fica_indisponivel():
    svc, *_ = service(env(dados=farmacia_simples()), env(dados=compras()),
                      FakeCatalog(error=CatalogUnavailable("banco fora")))
    r = await svc.get("u1", "g1", CNPJ)
    assert r["status"] == "indisponivel" and r["principal"] is None


# ─── Rota ───────────────────────────────────────────────────────────────


class FakeDiagnosis:
    def __init__(self):
        self.calls, self.error = [], None

    async def get(self, uid, group_id, cnpj):
        self.calls.append((uid, group_id, cnpj))
        if self.error:
            raise self.error
        return {"status": "ok"}


@pytest.fixture
def api(monkeypatch):
    fake = FakeDiagnosis()
    monkeypatch.setattr(main, "tax_diagnosis_service", fake)
    return TestClient(main.app), fake


def _auth():
    return {"Authorization": f"Bearer {mint_internal_token('uid-1')['token']}"}


def test_rota_passa_identidade(api):
    client, fake = api
    r = client.get(f"/diagnostico/tributario?group_id=g1&cnpj={CNPJ}", headers=_auth())
    assert r.status_code == 200 and fake.calls == [("uid-1", "g1", CNPJ)]


def test_rota_erros(api):
    client, fake = api
    url = f"/diagnostico/tributario?group_id=g1&cnpj={CNPJ}"
    assert client.get(url).status_code == 422
    fake.error = NotGroupMemberError("fora")
    assert client.get(url, headers=_auth()).status_code == 403
    fake.error = CrmNotAvailableError("sem CRM")
    assert client.get(url, headers=_auth()).status_code == 403
    fake.error = CompanyNotInPortfolioError("não")
    assert client.get(url, headers=_auth()).status_code == 404
