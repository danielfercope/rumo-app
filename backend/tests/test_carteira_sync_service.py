import uuid

import pytest
from cryptography.fernet import Fernet

from app.config import settings
from app.errors import (
    CnpjNotFoundError,
    InvalidCrmTokenError,
    UpstreamIntegrationError,
)
from app.services.carteira_sync_service import CarteiraSyncService
from app.services.crm_connector import CrmRecord
from app.services.token_cipher import TokenCipher
from tests.test_crm_sync_service import FakeGeocoder, FakeLookup

NOW = 1_700_000_000.0
NOW_MS = int(NOW * 1000)
GROUP_A = "00000000-0000-0000-0000-00000000000a"
GROUP_B = "00000000-0000-0000-0000-00000000000b"
CNPJ_1 = "19131243000197"
CNPJ_2 = "11222333000181"
CNPJ_3 = "45997418000153"


class FakeDb:
    """PostgrestClient em memória, o suficiente pro CarteiraSyncService."""

    TABLES = (
        "companies",
        "crm_conexoes",
        "sincronizacoes",
        "carteira_empresas",
        "carteira_pendencias",
        "group_members",
    )

    def __init__(self):
        self.tables: dict[str, list[dict]] = {t: [] for t in self.TABLES}
        self.calls: list[tuple[str, str]] = []

    @property
    def writes(self):
        return [c for c in self.calls if c[0] != "select"]

    def add_company(self, cnpj):
        company = {"id": str(uuid.uuid4()), "cnpj": cnpj}
        self.tables["companies"].append(company)
        return company

    def carteira(self, group_id):
        by_id = {c["id"]: c["cnpj"] for c in self.tables["companies"]}
        return {
            by_id[r["company_id"]]: r["status"]
            for r in self.tables["carteira_empresas"]
            if r["group_id"] == group_id
        }

    @staticmethod
    def _match(row, params):
        for column, expr in params.items():
            if column in ("select", "order", "limit"):
                continue
            op, _, value = expr.partition(".")
            actual = row.get(column)
            if op == "eq" and str(actual) != value:
                return False
            if op == "in" and str(actual) not in value.strip("()").split(","):
                return False
            if op == "lte" and not str(actual) <= value:
                return False
            if op == "lt" and not int(actual) < int(value):
                return False
        return True

    async def select(self, table, params):
        self.calls.append(("select", table))
        return [dict(r) for r in self.tables[table] if self._match(r, params)]

    async def insert(self, table, rows, *, on_conflict=None, ignore_duplicates=False):
        self.calls.append(("insert", table))
        for row in rows:
            if on_conflict and any(
                r[on_conflict] == row[on_conflict] for r in self.tables[table]
            ):
                if ignore_duplicates:
                    continue
                raise AssertionError("conflito sem ignore_duplicates")
            new = dict(row)
            if table == "companies":
                new["id"] = str(uuid.uuid4())
            self.tables[table].append(new)

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
                new = dict(row)
                if table == "crm_conexoes":  # default gen_random_uuid() do banco
                    new.setdefault("id", str(uuid.uuid4()))
                self.tables[table].append(new)

    async def update(self, table, params, values):
        self.calls.append(("update", table))
        for row in self.tables[table]:
            if self._match(row, params):
                row.update(values)

    async def delete(self, table, params):
        self.calls.append(("delete", table))
        self.tables[table] = [
            r for r in self.tables[table] if not self._match(r, params)
        ]


class FakeConnector:
    def __init__(self, pages=None, error=None, error_after_pages=None):
        self.pages = pages or []
        self.error = error
        self.error_after_pages = error_after_pages
        self.since_calls: list[int | None] = []
        self.closed = False

    async def fetch_changes(self, since_ms, mapping):
        self.since_calls.append(since_ms)
        if self.error and self.error_after_pages is None:
            raise self.error
        for page in self.pages:
            yield page
        if self.error:
            raise self.error

    async def aclose(self):
        self.closed = True


def rec(external_id, cnpj, stage="lead", modified=NOW_MS - 3_600_000, **signals):
    return CrmRecord(str(external_id), cnpj, stage, modified, **signals)


KEY = Fernet.generate_key().decode()


@pytest.fixture
def db():
    return FakeDb()


@pytest.fixture
def cipher():
    return TokenCipher(KEY)


@pytest.fixture
def lookup():
    return FakeLookup()


@pytest.fixture
def clock():
    state = {"now": NOW}
    return state


@pytest.fixture
def make_conexao(db, cipher):
    def factory(group_id=GROUP_A, **overrides):
        conexao = {
            "id": str(uuid.uuid4()),
            "group_id": group_id,
            "provedor": "hubspot",
            "token_cifrado": cipher.encrypt("token-da-org"),
            "mapeamento": {},
            "situacao": "pendente",
            "ultimo_erro": None,
            "ultima_modificacao_crm": None,
            "ultima_sincronizacao": None,
            **overrides,
        }
        db.tables["crm_conexoes"].append(conexao)
        return conexao

    return factory


@pytest.fixture
def make_service(db, lookup, cipher, clock):
    def factory(connector, *, lookup_=None, priority=None):
        async def no_sleep(_):
            pass

        return CarteiraSyncService(
            db,
            lookup_ or lookup,
            FakeGeocoder(),
            cipher,
            lambda provedor, token: connector,
            company_pause=0,
            clock=lambda: clock["now"],
            sleep=no_sleep,
            priority=priority,
        )

    return factory


def _conexao_row(db, conexao):
    return next(c for c in db.tables["crm_conexoes"] if c["id"] == conexao["id"])


# ─── Carga inicial ──────────────────────────────────────────────────────


async def test_carga_inicial_importa_empresas_e_grava_a_carteira(
    db, lookup, make_conexao, make_service
):
    conexao = make_conexao(
        mapeamento={"status": {"cliente": ["customer"], "perdido": ["other"]}}
    )
    connector = FakeConnector(
        [
            [
                rec(1, "19.131.243/0001-97", "customer", NOW_MS - 3000),
                rec(2, CNPJ_2, "lead", NOW_MS - 2000),
                rec(3, CNPJ_3, "other", NOW_MS - 1000),
            ]
        ]
    )

    result = await make_service(connector).sync_connection(conexao)

    assert (result.lidas, result.novas, result.falhas) == (3, 3, 0)
    assert sorted(lookup.calls) == sorted([CNPJ_1, CNPJ_2, CNPJ_3])
    assert db.carteira(GROUP_A) == {
        CNPJ_1: "cliente",
        CNPJ_2: "lead",
        CNPJ_3: "perdido",
    }
    row = db.tables["carteira_empresas"][0]
    assert row["origem"] == "crm" and row["crm_object_id"] == "1"

    saved = _conexao_row(db, conexao)
    assert saved["situacao"] == "ativa"
    assert saved["ultimo_erro"] is None
    assert saved["ultima_modificacao_crm"].startswith("2023-11-14T22:13:19")
    assert connector.closed
    # a carga inicial conta as empresas antes (pro progresso) e depois importa
    assert connector.since_calls == [None, None]

    (log,) = db.tables["sincronizacoes"]
    assert (log["tipo"], log["situacao"]) == ("carga_inicial", "concluida")
    assert (log["total_lidas"], log["total_novas"]) == (3, 3)
    assert (log["total_estimado"], log["total_processadas"]) == (3, 3)
    assert log["group_id"] == GROUP_A and log["conexao_id"] == conexao["id"]


async def test_empresa_ja_cadastrada_so_ganha_o_vinculo(
    db, lookup, make_conexao, make_service
):
    db.add_company(CNPJ_1)  # trazida antes por outra organização ou pelo app
    conexao = make_conexao()

    result = await make_service(FakeConnector([[rec(1, CNPJ_1, "customer")]])).sync_connection(
        conexao
    )

    assert result.novas == 1
    assert lookup.calls == []  # sem reconsultar BrasilAPI/Google
    assert len(db.tables["companies"]) == 1
    assert db.carteira(GROUP_A) == {CNPJ_1: "cliente"}  # padrão: customer = cliente


async def test_organizacoes_enxergam_a_mesma_empresa_com_status_proprio(
    db, lookup, make_conexao, make_service
):
    conexao_a = make_conexao(GROUP_A)
    conexao_b = make_conexao(GROUP_B, mapeamento={"status": {"perdido": ["lead"]}})

    await make_service(FakeConnector([[rec(1, CNPJ_1, "customer")]])).sync_connection(
        conexao_a
    )
    await make_service(FakeConnector([[rec(9, CNPJ_1, "lead")]])).sync_connection(
        conexao_b
    )

    assert len(db.tables["companies"]) == 1
    assert lookup.calls == [CNPJ_1]  # enriquecida uma vez só
    assert db.carteira(GROUP_A) == {CNPJ_1: "cliente"}
    assert db.carteira(GROUP_B) == {CNPJ_1: "perdido"}


async def test_cnpj_invalido_e_ignorado(db, lookup, make_conexao, make_service):
    conexao = make_conexao()
    connector = FakeConnector([[rec(1, "123"), rec(2, None), rec(3, CNPJ_2)]])

    result = await make_service(connector).sync_connection(conexao)

    assert (result.lidas, result.ignoradas, result.novas) == (3, 2, 1)
    assert lookup.calls == [CNPJ_2]


# ─── Incremental ────────────────────────────────────────────────────────


async def test_incremental_usa_marca_dagua_com_sobreposicao_e_atualiza_status(
    db, make_conexao, make_service
):
    company = db.add_company(CNPJ_1)
    conexao = make_conexao(
        situacao="ativa", ultima_modificacao_crm="2023-11-14T22:00:00+00:00"
    )
    db.tables["carteira_empresas"].append(
        {
            "group_id": GROUP_A,
            "company_id": company["id"],
            "status": "cliente",
            "crm_object_id": "1",
        }
    )
    connector = FakeConnector(
        [[rec(1, CNPJ_1, "other", NOW_MS - 1000), rec(2, CNPJ_2, "lead", NOW_MS - 500)]]
    )
    conexao["mapeamento"] = {"status": {"cliente": ["customer"], "perdido": ["other"]}}

    result = await make_service(connector).sync_connection(conexao)

    window_ms = settings.crm_sync_overlap_minutes * 60_000
    watermark_ms = 1_699_999_200_000  # 2023-11-14T22:00:00Z
    assert connector.since_calls == [watermark_ms - window_ms]
    assert (result.atualizadas, result.novas, result.sem_mudanca) == (1, 1, 0)
    assert db.carteira(GROUP_A) == {CNPJ_1: "perdido", CNPJ_2: "lead"}
    (log,) = db.tables["sincronizacoes"]
    assert log["tipo"] == "incremental"


async def test_incremental_sem_novidade_so_atualiza_a_conexao(
    db, make_conexao, make_service
):
    company = db.add_company(CNPJ_1)
    conexao = make_conexao(
        situacao="ativa",
        ultima_modificacao_crm="2023-11-14T22:00:00+00:00",
        mapeamento={"status": {"cliente": ["customer"]}},
    )
    db.tables["carteira_empresas"].append(
        {
            "group_id": GROUP_A,
            "company_id": company["id"],
            "status": "cliente",
            "crm_object_id": "1",
        }
    )
    # Registro reaparecido pela janela de sobreposição, sem mudança.
    connector = FakeConnector([[rec(1, CNPJ_1, "customer", modified=1_699_999_000_000)]])

    result = await make_service(connector).sync_connection(conexao)

    assert (result.sem_mudanca, result.novas, result.atualizadas) == (1, 0, 0)
    assert db.writes == [("update", "crm_conexoes")]  # só ultima_sincronizacao
    assert db.tables["sincronizacoes"] == []  # nenhum log sem novidade


# ─── Falhas por empresa e retentativa ───────────────────────────────────


async def test_falha_no_enriquecimento_vai_pra_fila_e_e_retentada_apos_o_backoff(
    db, cipher, clock, make_conexao, make_service
):
    conexao = make_conexao(mapeamento={"status": {"cliente": ["customer"]}})
    record = rec(1, CNPJ_1, "customer", NOW_MS - 1000)

    # 1º ciclo: BrasilAPI não acha o CNPJ.
    result = await make_service(
        FakeConnector([[record]]),
        lookup_=FakeLookup(error=CnpjNotFoundError("nada")),
    ).sync_connection(conexao)

    assert (result.falhas, result.novas) == (1, 0)
    (pending,) = db.tables["carteira_pendencias"]
    assert pending["conexao_id"] == conexao["id"]
    assert (pending["cnpj"], pending["status"], pending["attempts"]) == (
        CNPJ_1,
        "cliente",
        1,
    )
    assert db.tables["carteira_empresas"] == []
    # A marca d'água avança além da falha.
    assert _conexao_row(db, conexao)["ultima_modificacao_crm"] is not None

    # 2º ciclo logo depois: o mesmo registro reaparece (janela de sobreposição)
    # mas o backoff ainda não venceu — não reconsulta.
    lookup_ok = FakeLookup()
    await make_service(FakeConnector([[record]]), lookup_=lookup_ok).sync_connection(
        _conexao_row(db, conexao)
    )
    assert lookup_ok.calls == []
    assert len(db.tables["carteira_pendencias"]) == 1

    # 3º ciclo, backoff vencido: retenta e conclui, saindo da fila.
    clock["now"] = NOW + 3 * 3600
    result = await make_service(FakeConnector([]), lookup_=lookup_ok).sync_connection(
        _conexao_row(db, conexao)
    )
    assert result.novas == 1
    assert lookup_ok.calls == [CNPJ_1]
    assert db.carteira(GROUP_A) == {CNPJ_1: "cliente"}
    assert db.tables["carteira_pendencias"] == []


async def test_pendencia_nao_vaza_entre_conexoes(db, make_conexao, make_service):
    conexao_a = make_conexao(GROUP_A)
    conexao_b = make_conexao(GROUP_B)
    record = rec(1, CNPJ_1)  # mesmo id de objeto nas duas contas de CRM

    await make_service(
        FakeConnector([[record]]),
        lookup_=FakeLookup(error=CnpjNotFoundError("nada")),
    ).sync_connection(conexao_a)
    lookup_b = FakeLookup()
    await make_service(FakeConnector([[record]]), lookup_=lookup_b).sync_connection(
        conexao_b
    )

    assert lookup_b.calls == [CNPJ_1]  # a pendência da A não bloqueia a B
    assert db.carteira(GROUP_B) == {CNPJ_1: "lead"}
    assert db.carteira(GROUP_A) == {}


# ─── Erros da conexão ───────────────────────────────────────────────────


async def test_token_recusado_marca_a_conexao_com_erro(
    db, make_conexao, make_service
):
    conexao = make_conexao(situacao="ativa")
    connector = FakeConnector(error=InvalidCrmTokenError("token revogado"))

    await make_service(connector).sync_connection(conexao)

    saved = _conexao_row(db, conexao)
    assert saved["situacao"] == "erro"
    assert "revogado" in saved["ultimo_erro"]
    assert saved["ultima_sincronizacao"] is None
    assert connector.closed
    (log,) = db.tables["sincronizacoes"]
    assert log["situacao"] == "erro"


async def test_token_ilegivel_marca_a_conexao_com_erro(db, make_conexao, make_service):
    conexao = make_conexao(situacao="ativa", token_cifrado="lixo")

    await make_service(FakeConnector()).sync_connection(conexao)

    saved = _conexao_row(db, conexao)
    assert saved["situacao"] == "erro"
    assert "reconectar" in saved["ultimo_erro"]


async def test_falha_transitoria_mantem_a_situacao_e_o_progresso(
    db, make_conexao, make_service
):
    conexao = make_conexao(situacao="pendente")
    connector = FakeConnector(
        pages=[[rec(1, CNPJ_1, modified=NOW_MS - 5000)]],
        error=UpstreamIntegrationError("429"),
        error_after_pages=1,
    )

    await make_service(connector).sync_connection(conexao)

    saved = _conexao_row(db, conexao)
    assert saved["situacao"] == "pendente"  # não virou 'ativa' nem 'erro'
    assert "429" in saved["ultimo_erro"]
    assert db.carteira(GROUP_A) == {CNPJ_1: "lead"}  # o que veio foi gravado
    assert saved["ultima_modificacao_crm"] is not None  # retoma dali


# ─── Ciclo ──────────────────────────────────────────────────────────────


async def test_run_cycle_so_processa_conexoes_ativas(db, make_conexao, make_service):
    ativa = make_conexao(GROUP_A, situacao="ativa")
    make_conexao(GROUP_B, situacao="pendente")
    make_conexao(GROUP_B, situacao="desconectada")
    connector = FakeConnector([[rec(1, CNPJ_1)]])

    results = await make_service(connector).run_cycle()

    assert list(results) == [ativa["id"]]
    assert len(connector.since_calls) == 2  # contagem prévia + importação


# ─── Sinais de priorização (criação e interação no CRM) ─────────────────


async def test_grava_sinais_de_interacao_na_carteira(db, make_conexao, make_service):
    conexao = make_conexao()
    connector = FakeConnector(
        [
            [
                rec(
                    1,
                    CNPJ_1,
                    created_at_ms=1672531200000,
                    last_interaction_ms=1700000000000,
                    interactions=4,
                )
            ]
        ]
    )

    await make_service(connector).sync_connection(conexao)

    row = db.tables["carteira_empresas"][0]
    assert row["crm_criado_em"].startswith("2023-01-01T00:00:00")
    assert row["ultima_interacao_em"].startswith("2023-11-14T22:13:20")
    assert row["num_interacoes"] == 4


async def test_mudanca_so_nos_sinais_atualiza_a_linha(db, make_conexao, make_service):
    company = db.add_company(CNPJ_1)
    conexao = make_conexao(situacao="ativa")
    db.tables["carteira_empresas"].append(
        {
            "group_id": GROUP_A,
            "company_id": company["id"],
            "status": "lead",
            "crm_object_id": "1",
            "crm_criado_em": "2023-01-01T00:00:00+00:00",
            "ultima_interacao_em": None,
            "num_interacoes": 1,
        }
    )
    # mesmo status e mesmo id; só a contagem de interações mudou, e o instante
    # da criação vem no mesmo valor mas com outra grafia (Z vs +00:00)
    connector = FakeConnector(
        [[rec(1, CNPJ_1, created_at_ms=1672531200000, interactions=2)]]
    )

    result = await make_service(connector).sync_connection(conexao)

    assert (result.atualizadas, result.sem_mudanca) == (1, 0)
    assert db.tables["carteira_empresas"][0]["num_interacoes"] == 2


async def test_sinais_iguais_em_outra_grafia_nao_regravam(
    db, make_conexao, make_service
):
    company = db.add_company(CNPJ_1)
    conexao = make_conexao(situacao="ativa")
    db.tables["carteira_empresas"].append(
        {
            "group_id": GROUP_A,
            "company_id": company["id"],
            "status": "lead",
            "crm_object_id": "1",
            "crm_criado_em": "2023-01-01T00:00:00Z",
            "ultima_interacao_em": None,
            "num_interacoes": 3,
        }
    )
    connector = FakeConnector(
        [[rec(1, CNPJ_1, created_at_ms=1672531200000, interactions=3)]]
    )

    result = await make_service(connector).sync_connection(conexao)

    assert (result.atualizadas, result.sem_mudanca) == (0, 1)


# ─── Recálculo da prioridade ao fim da sincronização ────────────────────


class FakePriority:
    def __init__(self, has_result=True, error=None):
        self._has_result, self.error = has_result, error
        self.recalculated: list[str] = []

    async def has_result(self, group_id):
        return self._has_result

    async def recalculate(self, group_id):
        self.recalculated.append(group_id)
        if self.error:
            raise self.error


async def test_recalcula_a_prioridade_quando_a_carteira_mudou(
    db, make_conexao, make_service
):
    priority = FakePriority()
    conexao = make_conexao()
    connector = FakeConnector([[rec(1, CNPJ_1)]])

    await make_service(connector, priority=priority).sync_connection(conexao)

    assert priority.recalculated == [GROUP_A]


async def test_sem_mudanca_e_com_resultado_nao_recalcula(
    db, make_conexao, make_service
):
    priority = FakePriority(has_result=True)
    conexao = make_conexao(
        situacao="ativa", ultima_modificacao_crm="2023-11-14T22:00:00+00:00"
    )

    await make_service(FakeConnector([]), priority=priority).sync_connection(conexao)

    assert priority.recalculated == []


async def test_sem_mudanca_mas_sem_resultado_calcula_uma_vez(
    db, make_conexao, make_service
):
    priority = FakePriority(has_result=False)
    conexao = make_conexao(
        situacao="ativa", ultima_modificacao_crm="2023-11-14T22:00:00+00:00"
    )

    await make_service(FakeConnector([]), priority=priority).sync_connection(conexao)

    assert priority.recalculated == [GROUP_A]


async def test_falha_no_recalculo_nao_derruba_a_sincronizacao(
    db, make_conexao, make_service
):
    priority = FakePriority(error=RuntimeError("banco caiu"))
    conexao = make_conexao()
    connector = FakeConnector([[rec(1, CNPJ_1)]])

    result = await make_service(connector, priority=priority).sync_connection(conexao)

    assert result.novas == 1
    assert db.carteira(GROUP_A) == {CNPJ_1: "lead"}
    assert _conexao_row(db, conexao)["situacao"] == "ativa"


async def test_carga_inicial_grava_o_progresso_enquanto_roda(
    db, lookup, make_conexao, make_service, monkeypatch
):
    from app.services import carteira_sync_service as mod

    monkeypatch.setattr(mod, "PROGRESS_EVERY", 2)
    cnpjs = [CNPJ_1, CNPJ_2, CNPJ_3, "04252011000110", "33000167000101"]
    connector = FakeConnector(
        [[rec(i + 1, c, "lead", NOW_MS - 1000 + i) for i, c in enumerate(cnpjs)]]
    )
    seen: list[tuple] = []
    original = db.update

    async def spy(table, filters, values):
        if table == "sincronizacoes" and "total_estimado" in values:
            seen.append((values["total_estimado"], values["total_processadas"]))
        return await original(table, filters, values)

    monkeypatch.setattr(db, "update", spy)

    await make_service(connector).sync_connection(make_conexao())

    # estimativa gravada antes de importar; depois o contador sobe de 2 em 2
    assert seen[0] == (5, 0)
    assert [p for _, p in seen] == sorted(p for _, p in seen)
    assert (5, 2) in seen and (5, 4) in seen and seen[-1] == (5, 5)


async def test_falha_ao_gravar_o_progresso_nao_derruba_a_carga(
    db, lookup, make_conexao, make_service, monkeypatch
):
    connector = FakeConnector([[rec(1, CNPJ_1, "customer")]])
    original = db.update

    async def flaky(table, filters, values):
        if table == "sincronizacoes" and "total_estimado" in values:
            raise RuntimeError("banco indisponível")
        return await original(table, filters, values)

    monkeypatch.setattr(db, "update", flaky)

    result = await make_service(connector).sync_connection(make_conexao())

    assert result.novas == 1 and result.falhas == 0
