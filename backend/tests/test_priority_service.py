from datetime import datetime, timezone

import pytest
from fastapi.testclient import TestClient

from app import main
from app.errors import NotGroupMemberError
from app.internal_token import mint_internal_token
from app.services.priority_score import MIN_CLIENTS, PriorityModel
from app.services.priority_service import MAX_LIMIT, PAGE, PriorityService, choose_strategy

GROUP = "g1"
OTHER = "g2"
NOW = datetime(2024, 6, 1, tzinfo=timezone.utc)
LATER = datetime(2024, 6, 2, tzinfo=timezone.utc)
KEYS = {
    "prioridade_modelos": ("group_id",),
    "carteira_prioridade": ("group_id", "company_id"),
}


class FakeDb:
    """PostgrestClient em memória: eq/in/lt, order, limit/offset, embed de
    companies, upsert e delete — o que o PriorityService usa."""

    def __init__(self):
        self.tables = {
            "group_members": [],
            "carteira_empresas": [],
            "companies": [],
            "prioridade_modelos": [],
            "carteira_prioridade": [],
        }
        self.calls = []

    @staticmethod
    def _match(r, params):
        for col, expr in params.items():
            if col in ("select", "order", "limit", "offset"):
                continue
            op, _, val = expr.partition(".")
            actual = str(r.get(col))
            if op == "eq" and actual != val:
                return False
            if op == "in" and actual not in val.strip("()").split(","):
                return False
            if op == "lt" and not actual < val:
                return False
        return True

    async def select(self, table, params):
        self.calls.append(("select", table))
        rows = [dict(r) for r in self.tables[table] if self._match(r, params)]
        if "order" in params:
            col, _, direction = params["order"].partition(".")
            rows.sort(key=lambda r: r[col], reverse=direction == "desc")
        if "companies(" in params.get("select", ""):
            by_id = {c["id"]: c for c in self.tables["companies"]}
            for r in rows:
                r["companies"] = by_id.get(r["company_id"])
        off = int(params.get("offset", 0))
        lim = int(params.get("limit", len(rows)))
        return rows[off : off + lim]

    async def upsert(self, table, rows, on_conflict):
        self.calls.append(("upsert", table))
        keys = on_conflict.split(",")
        for row in rows:
            existing = next(
                (
                    r
                    for r in self.tables[table]
                    if all(r[k] == row[k] for k in keys)
                ),
                None,
            )
            if existing:
                existing.update(row)
            else:
                self.tables[table].append(dict(row))

    async def delete(self, table, params):
        self.calls.append(("delete", table))
        self.tables[table] = [
            r for r in self.tables[table] if not self._match(r, params)
        ]


@pytest.fixture
def db():
    d = FakeDb()
    d.tables["group_members"].append({"group_id": GROUP, "user_id": "u1", "role": "member"})
    return d


def add(db, i, status, *, group=GROUP, segmento="farmácia", inter=None, criado=None):
    cid = f"c{i:04d}"
    db.tables["companies"].append(
        {
            "id": cid,
            "cnpj": f"{i:014d}",
            "razao_social": f"Empresa {i}",
            "nome_fantasia": None,
            "segmento": segmento,
            "cnae_principal": "4771701" if segmento == "farmácia" else "5611201",
            "uf": "SC",
            "municipio": "Joinville",
            "porte": "me",
            "natureza_juridica": "ltda",
            "data_abertura": "2015-01-01",
        }
    )
    db.tables["carteira_empresas"].append(
        {
            "group_id": group,
            "company_id": cid,
            "status": status,
            "crm_criado_em": criado,
            "ultima_interacao_em": None,
            "num_interacoes": inter,
        }
    )
    return cid


def service(db, now=NOW):
    return PriorityService(db, clock=lambda: now)


def stored(db, group=GROUP):
    rows = [r for r in db.tables["carteira_prioridade"] if r["group_id"] == group]
    return sorted(rows, key=lambda r: r["posicao"])


def test_seletor_pelo_numero_de_clientes():
    assert choose_strategy(0) == "interacao"
    assert choose_strategy(MIN_CLIENTS - 1) == "interacao"
    assert choose_strategy(MIN_CLIENTS) == "perfil"


# ─── Cálculo ────────────────────────────────────────────────────────────


async def test_poucos_clientes_ordena_por_interacao_e_desempata_pelo_mais_antigo(db):
    for i in range(3):
        add(db, i, "cliente")
    a = add(db, 10, "lead", inter=2, criado="2023-01-01T00:00:00+00:00")
    b = add(db, 11, "lead", inter=5, criado="2024-01-01T00:00:00+00:00")
    c = add(db, 12, "lead", inter=2, criado="2022-01-01T00:00:00+00:00")
    add(db, 13, "perdido", inter=99)  # só lead entra no ranking

    await service(db).recalculate(GROUP)

    assert [r["company_id"] for r in stored(db)] == [b, c, a]
    assert [r["posicao"] for r in stored(db)] == [1, 2, 3]
    assert stored(db)[0]["nota"] is None
    assert stored(db)[0]["motivos"] == ["5 interações · no CRM há 152 dias"]
    (meta,) = db.tables["prioridade_modelos"]
    assert (meta["estrategia"], meta["n_clientes"], meta["n_leads"]) == ("interacao", 3, 3)
    assert meta["modelo"] is None


async def test_com_clientes_suficientes_usa_o_perfil_guarda_o_modelo_e_explica(db):
    for i in range(MIN_CLIENTS):
        add(db, i, "cliente", segmento="farmácia")
    parecido = add(db, 100, "lead", segmento="farmácia")
    diferente = add(db, 101, "lead", segmento="restaurante")
    for i in range(200, 260):  # base: o resto do mercado
        add(db, i, "lead", segmento="restaurante", group=OTHER)

    await service(db).recalculate(GROUP)

    rows = stored(db)
    assert [r["company_id"] for r in rows] == [parecido, diferente]
    assert (rows[0]["nota"], rows[1]["nota"]) == (100, 0)
    assert any("Segmento: farmácia" in m for m in rows[0]["motivos"])
    (meta,) = db.tables["prioridade_modelos"]
    assert meta["estrategia"] == "perfil"
    # o modelo guardado é utilizável: reconstrói e pontua como o original
    model = PriorityModel.from_json(meta["modelo"])
    assert model.reliable
    farmacia = db.tables["companies"][0]
    assert model.score(farmacia).raw > 0


async def test_recalculo_remove_quem_deixou_de_ser_lead_e_nao_duplica(db):
    for i in range(3):
        add(db, i, "cliente")
    a = add(db, 10, "lead", inter=1)
    b = add(db, 11, "lead", inter=2)
    await service(db).recalculate(GROUP)
    assert len(stored(db)) == 2

    next(r for r in db.tables["carteira_empresas"] if r["company_id"] == b)[
        "status"
    ] = "cliente"
    await service(db, LATER).recalculate(GROUP)

    assert [r["company_id"] for r in stored(db)] == [a]
    assert stored(db)[0]["posicao"] == 1
    assert db.tables["prioridade_modelos"][0]["n_clientes"] == 4
    assert len(db.tables["prioridade_modelos"]) == 1


async def test_recalculo_so_mexe_na_propria_organizacao(db):
    add(db, 1, "lead", inter=1)
    add(db, 2, "lead", group=OTHER, inter=1)
    db.tables["carteira_prioridade"].append(
        {"group_id": OTHER, "company_id": "c0002", "posicao": 1, "nota": None,
         "motivos": [], "calculado_em": "2000-01-01T00:00:00+00:00"}
    )

    await service(db).recalculate(GROUP)

    assert len(stored(db, OTHER)) == 1  # intacta (e ainda velha)
    assert len(stored(db, GROUP)) == 1


async def test_clear_apaga_resultado_so_da_organizacao(db):
    add(db, 1, "lead", inter=1)
    add(db, 2, "lead", group=OTHER, inter=1)
    await service(db).recalculate(GROUP)
    await service(db).recalculate(OTHER)

    await service(db).clear(GROUP)

    assert stored(db) == [] and len(stored(db, OTHER)) == 1
    assert [m["group_id"] for m in db.tables["prioridade_modelos"]] == [OTHER]


async def test_has_result(db):
    add(db, 1, "lead", inter=1)
    assert not await service(db).has_result(GROUP)
    await service(db).recalculate(GROUP)
    assert await service(db).has_result(GROUP)


async def test_le_a_carteira_paginada(db):
    for i in range(PAGE + 5):
        add(db, i, "lead", inter=1)
    await service(db).recalculate(GROUP)
    assert db.tables["prioridade_modelos"][0]["n_leads"] == PAGE + 5
    assert len(stored(db)) == PAGE + 5


# ─── Leitura: nunca varre carteira nem base ─────────────────────────────


async def test_ranking_le_so_o_resultado_guardado(db):
    for i in range(3):
        add(db, i, "cliente")
    for i in range(10, 20):
        add(db, i, "lead", inter=i)
    add(db, 50, "lead", group=OTHER, inter=1000)
    await service(db).recalculate(GROUP)
    db.calls.clear()

    out = await service(db).ranking("u1", GROUP, limit=4)

    assert [i["posicao"] for i in out["itens"]] == [1, 2, 3, 4]
    assert out["itens"][0]["company_id"] == "c0019"
    assert out["itens"][0]["nome"] == "Empresa 19"
    assert out["itens"][0]["municipio"] == "Joinville"
    assert (out["estrategia"], out["n_clientes"], out["n_leads"]) == ("interacao", 3, 10)
    tabelas = {t for _, t in db.calls}
    assert tabelas == {"group_members", "prioridade_modelos", "carteira_prioridade"}
    assert all(op == "select" for op, _ in db.calls)


async def test_ranking_compacto_devolve_a_carteira_toda_so_com_id_posicao_e_nota(db):
    for i in range(3):
        add(db, i, "cliente")
    for i in range(10, 10 + MAX_LIMIT + 50):  # mais que o limite do modo normal
        add(db, i, "lead", inter=i)
    await service(db).recalculate(GROUP)

    selects = []
    original = db.select

    async def spy(table, params):
        if table == "carteira_prioridade":
            selects.append(params["select"])
        return await original(table, params)

    db.select = spy
    normal = await service(db).ranking("u1", GROUP, limit=100_000)
    compacto = await service(db).ranking("u1", GROUP, limit=100_000, compact=True)

    assert len(normal["itens"]) == MAX_LIMIT
    assert len(compacto["itens"]) == MAX_LIMIT + 50
    # o modo compacto não pede nome nem motivos (nem faz a junção com companies)
    assert selects[1] == "company_id,posicao,nota" and "motivos" in selects[0]


async def test_ranking_sem_calculo_ainda_devolve_vazio(db):
    out = await service(db).ranking("u1", GROUP)
    assert out["estrategia"] is None and out["itens"] == []


async def test_nao_membro_e_barrado_sem_ler_o_resultado(db):
    add(db, 1, "lead")
    await service(db).recalculate(GROUP)
    db.calls.clear()
    with pytest.raises(NotGroupMemberError):
        await service(db).ranking("intruso", GROUP)
    assert [t for _, t in db.calls] == ["group_members"]


# ─── Explicação de um lead ──────────────────────────────────────────────


async def _carteira_de_perfil(db):
    for i in range(MIN_CLIENTS):
        add(db, i, "cliente", segmento="farmácia")
    parecido = add(db, 100, "lead", segmento="farmácia")
    diferente = add(db, 101, "lead", segmento="restaurante")
    for i in range(200, 260):
        add(db, i, "lead", segmento="restaurante", group=OTHER)
    await service(db).recalculate(GROUP)
    return parecido, diferente


async def test_explica_fatores_a_favor_e_contra_com_os_numeros(db):
    parecido, diferente = await _carteira_de_perfil(db)

    a = await service(db).explain("u1", GROUP, parecido)
    b = await service(db).explain("u1", GROUP, diferente)

    assert a["disponivel"] and (a["posicao"], a["nota"], a["total_leads"]) == (1, 100, 2)
    assert a["n_clientes"] == MIN_CLIENTS and a["confiavel"] is True
    seg = next(f for f in a["fatores"] if f["chave"] == "segmento")
    assert seg["valor"] == "Farmácia" and seg["efeito"] == "favorece"
    assert seg["pct_clientes"] == 1.0 and seg["clientes_com_valor"] == MIN_CLIENTS
    assert seg["vezes"] > 1
    # o mesmo fator, pro lead diferente, atrapalha
    seg_b = next(f for f in b["fatores"] if f["chave"] == "segmento")
    assert seg_b["efeito"] == "desfavorece" and seg_b["contribuicao"] < 0
    # ordem: do que mais ajuda ao que mais atrapalha
    contribs = [f["contribuicao"] for f in a["fatores"]]
    assert contribs == sorted(contribs, reverse=True)
    # característica que a empresa não tem não pune nem premia: é listada à parte
    assert "Faturamento" in a["sem_dado"]
    assert all(f["chave"] != "faixa_faturamento" for f in a["fatores"])
    assert next(f for f in a["fatores"] if f["chave"] == "municipio")["valor"] == "Joinville (SC)"


async def test_explicacao_so_le_e_exige_ser_membro(db):
    parecido, _ = await _carteira_de_perfil(db)
    db.calls.clear()
    await service(db).explain("u1", GROUP, parecido)
    assert all(op == "select" for op, _ in db.calls)
    assert {t for _, t in db.calls} <= {
        "group_members", "carteira_prioridade", "prioridade_modelos", "companies"}

    db.calls.clear()
    with pytest.raises(NotGroupMemberError):
        await service(db).explain("intruso", GROUP, parecido)
    assert [t for _, t in db.calls] == ["group_members"]


async def test_explicacao_de_empresa_fora_da_lista_nao_esta_disponivel(db):
    await _carteira_de_perfil(db)
    out = await service(db).explain("u1", GROUP, "c0000")  # é cliente, não lead
    assert out == {"disponivel": False}


async def test_explicacao_na_estrategia_por_interacao_traz_os_sinais_do_crm(db):
    for i in range(3):
        add(db, i, "cliente")
    lead = add(db, 10, "lead", inter=7, criado="2024-01-01T00:00:00+00:00")
    await service(db).recalculate(GROUP)

    out = await service(db).explain("u1", GROUP, lead)

    assert out["estrategia"] == "interacao" and out["fatores"] == []
    assert out["sinais"]["num_interacoes"] == 7
    assert out["motivos"]


# ─── Endpoint ───────────────────────────────────────────────────────────


class FakeRanking:
    def __init__(self, error=None):
        self.error, self.calls = error, []

    async def ranking(self, uid, group_id, limit, compact=False):
        self.calls.append((uid, group_id, limit) if not compact else (uid, group_id, limit, "compacto"))
        if self.error:
            raise self.error
        return {"estrategia": "interacao", "itens": []}


@pytest.fixture
def api(monkeypatch):
    fake = FakeRanking()
    monkeypatch.setattr(main, "priority_service", fake)
    return TestClient(main.app), fake


def _auth():
    return {"Authorization": f"Bearer {mint_internal_token('uid-1')['token']}"}


def test_endpoint_exige_token(api):
    client, fake = api
    assert client.get(f"/carteira/prioridade?group_id={GROUP}").status_code == 422
    r = client.get(
        f"/carteira/prioridade?group_id={GROUP}",
        headers={"Authorization": "Bearer lixo"},
    )
    assert r.status_code == 401 and fake.calls == []


def test_endpoint_passa_identidade_e_limite(api):
    client, fake = api
    r = client.get(f"/carteira/prioridade?group_id={GROUP}&limit=7", headers=_auth())
    assert r.status_code == 200
    assert fake.calls == [("uid-1", GROUP, 7)]


def test_endpoint_compacto_repassa_a_flag(api):
    client, fake = api
    r = client.get(
        f"/carteira/prioridade?group_id={GROUP}&limit=5000&compacto=true", headers=_auth())
    assert r.status_code == 200
    assert fake.calls == [("uid-1", GROUP, 5000, "compacto")]


def test_endpoint_responde_403_para_nao_membro(api):
    client, fake = api
    fake.error = NotGroupMemberError("Você não pertence a esta organização.")
    r = client.get(f"/carteira/prioridade?group_id={GROUP}", headers=_auth())
    assert r.status_code == 403


def test_endpoint_da_explicacao_passa_identidade_e_empresa(api, monkeypatch):
    client, _ = api
    seen = []

    class Fake:
        async def explain(self, uid, group_id, company_id):
            seen.append((uid, group_id, company_id))
            return {"disponivel": False}

    monkeypatch.setattr(main, "priority_service", Fake())
    r = client.get(
        f"/carteira/prioridade/empresa?group_id={GROUP}&company_id=c1", headers=_auth())
    assert r.status_code == 200 and seen == [("uid-1", GROUP, "c1")]
    assert client.get(
        f"/carteira/prioridade/empresa?group_id={GROUP}&company_id=c1").status_code == 422
