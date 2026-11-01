import asyncio
import json
import uuid

import httpx
import pytest
import respx

from app.config import settings
from app.errors import CnpjNotFoundError, GeocodingNotFoundError
from app.services.crm_service import BASE_URL, CrmService
from app.services.crm_sync_service import (
    CrmSyncService,
    build_company_row,
    build_geocoding_address,
)
from app.services.geocoding_service import Geocode

SEARCH_URL = f"{BASE_URL}/crm/v3/objects/companies/search"
NOW = 1_700_000_000.0
CNPJ = "19131243000197"

LOOKUP_DATA = {
    "cnpj": CNPJ,
    "razao": "ACME LTDA",
    "fantasia": "Acme",
    "email": "contato@acme.com",
    "site": None,
    "ddd_1": "47",
    "tel_1": "30001234",
    "log_tipo": "RUA",
    "log_nome": "DAS FLORES",
    "log_num": "10",
    "log_bairro": "CENTRO",
    "log_municipio": "JOINVILLE",
    "log_uf": "SC",
    "log_cep": "89201000",
    "situacao_cadastral": "ATIVA",
    "porte": "ME",
    "cnae_principal": "Comércio",
    "natureza_juridica": "Sociedade Limitada",
    "data_abertura": "20100315",
}


class FakeDb:
    """PostgrestClient em memória — só o suficiente pro CrmSyncService, com um
    log de chamadas pra provar quais tabelas cada ciclo toca."""

    def __init__(self):
        self.tables: dict[str, list[dict]] = {
            "companies": [],
            "company_crm_sync": [],
            "crm_sync_state": [],
            "crm_sync_pending": [],
        }
        self.calls: list[tuple[str, str]] = []

    @property
    def writes(self):
        return [c for c in self.calls if c[0] != "select"]

    def add_company(self, cnpj=CNPJ, crm_id=None):
        company = {"id": str(uuid.uuid4()), "cnpj": cnpj}
        self.tables["companies"].append(company)
        if crm_id:
            self.tables["company_crm_sync"].append(
                {"company_id": company["id"], "crm_object_id": crm_id}
            )
        return company

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
        rows = [r for r in self.tables[table] if self._match(r, params)]
        if table == "companies":
            rows = [
                {
                    **r,
                    "company_crm_sync": next(
                        (
                            {"crm_object_id": s["crm_object_id"]}
                            for s in self.tables["company_crm_sync"]
                            if s["company_id"] == r["id"]
                        ),
                        None,
                    ),
                }
                for r in rows
            ]
        return rows

    async def insert(self, table, rows, *, on_conflict=None, ignore_duplicates=False):
        self.calls.append(("insert", table))
        for row in rows:
            if on_conflict and any(
                r[on_conflict] == row[on_conflict] for r in self.tables[table]
            ):
                if ignore_duplicates:
                    continue
                raise AssertionError("conflito sem ignore_duplicates")
            self.tables[table].append({"id": str(uuid.uuid4()), **row})

    async def upsert(self, table, rows, on_conflict):
        self.calls.append(("upsert", table))
        for row in rows:
            existing = next(
                (r for r in self.tables[table] if r[on_conflict] == row[on_conflict]),
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


class FakeLookup:
    def __init__(self, error=None):
        self.error = error
        self.calls: list[str] = []

    async def lookup_cnpj(self, cnpj):
        self.calls.append(cnpj)
        if self.error:
            raise self.error
        return {**LOOKUP_DATA, "cnpj": cnpj}


class FakeGeocoder:
    def __init__(self, error=None):
        self.error = error
        self.calls: list[str] = []

    async def geocode(self, address):
        self.calls.append(address)
        if self.error:
            raise self.error
        return Geocode(-26.3, -48.8, "ROOFTOP")


def _crm_row(crm_id, cnpj=CNPJ):
    return {"id": str(crm_id), "properties": {"cnpj": cnpj, "name": "Acme"}}


@pytest.fixture
def db():
    fake = FakeDb()
    fake.tables["crm_sync_state"].append({"key": "companies", "last_crm_id": 100})
    return fake


@pytest.fixture
def lookup():
    return FakeLookup()


@pytest.fixture
def geocoder():
    return FakeGeocoder()


@pytest.fixture
def make_service(db, lookup, geocoder):
    def factory(sleep=None):
        async def no_sleep(_):
            pass

        return CrmSyncService(
            CrmService(client=httpx.AsyncClient(base_url=BASE_URL)),
            lookup,
            geocoder,
            db,
            clock=lambda: NOW,
            sleep=sleep or no_sleep,
        )

    return factory


def _mock_search(*pages):
    return respx.post(SEARCH_URL).mock(
        side_effect=[httpx.Response(200, json={"results": p}) for p in pages]
    )


@respx.mock
async def test_ciclo_sem_novidade_e_barato(make_service, db, lookup, geocoder):
    route = _mock_search([])

    result = await make_service().run_cycle()

    assert route.call_count == 1  # uma única chamada ao CRM
    assert db.writes == []  # nenhuma escrita
    # Nenhuma varredura: só a marca d'água e a fila de pendências (minúscula).
    assert {t for _, t in db.calls} == {"crm_sync_state", "crm_sync_pending"}
    assert lookup.calls == [] and geocoder.calls == []
    assert result.fetched == 0


@respx.mock
async def test_primeira_execucao_parte_do_maior_id_atual_sem_importar(
    make_service, db, lookup
):
    db.tables["crm_sync_state"].clear()
    route = _mock_search([{"id": "500"}])

    result = await make_service().run_cycle()

    assert result.initialized
    assert route.call_count == 1
    assert db.tables["crm_sync_state"][0]["last_crm_id"] == 500
    assert lookup.calls == []
    assert ("select", "companies") not in db.calls


@respx.mock
async def test_importa_empresa_nova_e_avanca_a_marca_dagua(
    make_service, db, lookup, geocoder
):
    _mock_search([_crm_row(101, cnpj="19.131.243/0001-97")])

    result = await make_service().run_cycle()

    assert result.imported == 1
    assert lookup.calls == [CNPJ]
    assert "RUA DAS FLORES, 10 - CENTRO, JOINVILLE - SC" in geocoder.calls
    [company] = db.tables["companies"]
    assert company["cnpj"] == CNPJ
    assert (company["latitude"], company["longitude"]) == (-26.3, -48.8)
    assert company["precisao_geocodificacao"] == "ROOFTOP"
    assert company["telefone_principal"] == "4730001234"
    assert company["data_abertura"] == "2010-03-15"
    [link] = db.tables["company_crm_sync"]
    assert link["company_id"] == company["id"]
    assert link["crm_object_id"] == "101"
    assert db.tables["crm_sync_state"][0]["last_crm_id"] == 101


@respx.mock
async def test_empresa_ja_cadastrada_pelo_app_so_ganha_o_vinculo(
    make_service, db, lookup, geocoder
):
    existing = db.add_company()  # cadastrada pelo app, sem vínculo com o CRM
    _mock_search([_crm_row(101)])

    result = await make_service().run_cycle()

    assert result.linked == 1 and result.imported == 0
    assert lookup.calls == [] and geocoder.calls == []
    assert ("insert", "companies") not in db.calls
    assert db.tables["company_crm_sync"][0]["company_id"] == existing["id"]


@respx.mock
async def test_reaparecer_na_janela_de_sobreposicao_nao_escreve_nada(
    make_service, db, lookup
):
    db.add_company(crm_id="90")  # já importada; id abaixo da marca d'água
    _mock_search([_crm_row(90)])

    result = await make_service().run_cycle()

    assert result.unchanged == 1
    assert db.writes == []
    assert lookup.calls == []


@respx.mock
async def test_falha_de_geocoding_vai_pra_fila_sem_travar_o_lote(
    make_service, db, lookup, geocoder
):
    geocoder.error = GeocodingNotFoundError("sem coordenadas")
    _mock_search([_crm_row(101)])

    result = await make_service().run_cycle()

    assert result.failed == 1
    assert db.tables["companies"] == []
    [pending] = db.tables["crm_sync_pending"]
    assert pending["crm_object_id"] == "101"
    assert pending["attempts"] == 1
    assert pending["next_retry_at"] > "2023-11-14T22:13:20+00:00"  # no futuro
    # A marca d'água avança além da empresa com falha.
    assert db.tables["crm_sync_state"][0]["last_crm_id"] == 101


@respx.mock
async def test_cnpj_invalido_e_ignorado(make_service, db, lookup):
    _mock_search([_crm_row(101, cnpj="123")])

    result = await make_service().run_cycle()

    assert result.skipped == 1
    assert lookup.calls == []
    assert db.tables["crm_sync_pending"] == []
    assert db.tables["crm_sync_state"][0]["last_crm_id"] == 101


@respx.mock
async def test_pendencia_vencida_e_retentada_e_removida(make_service, db):
    db.tables["crm_sync_pending"].append(
        {
            "crm_object_id": "80",
            "cnpj": CNPJ,
            "attempts": 1,
            "next_retry_at": "2000-01-01T00:00:00+00:00",
        }
    )
    _mock_search([])

    result = await make_service().run_cycle()

    assert result.imported == 1
    assert len(db.tables["companies"]) == 1
    assert db.tables["crm_sync_pending"] == []
    assert db.tables["company_crm_sync"][0]["crm_object_id"] == "80"


@respx.mock
async def test_pendencia_dentro_do_backoff_nao_e_retentada_nem_pela_janela(
    make_service, db, lookup
):
    db.tables["crm_sync_pending"].append(
        {
            "crm_object_id": "90",
            "cnpj": CNPJ,
            "attempts": 2,
            "next_retry_at": "2999-01-01T00:00:00+00:00",
        }
    )
    _mock_search([_crm_row(90)])  # reaparece pela janela de sobreposição

    await make_service().run_cycle()

    assert lookup.calls == []
    assert db.tables["crm_sync_pending"][0]["attempts"] == 2


@respx.mock
async def test_pendencia_que_falha_de_novo_acumula_tentativas(
    make_service, db, lookup
):
    lookup.error = CnpjNotFoundError("não achado")
    db.tables["crm_sync_pending"].append(
        {
            "crm_object_id": "80",
            "cnpj": CNPJ,
            "attempts": 2,
            "next_retry_at": "2000-01-01T00:00:00+00:00",
        }
    )
    _mock_search([])

    await make_service().run_cycle()

    assert db.tables["crm_sync_pending"][0]["attempts"] == 3


@respx.mock
async def test_backfill_pagina_por_id_e_grava_a_marca_dagua(
    make_service, db, lookup, monkeypatch
):
    monkeypatch.setattr(settings, "crm_sync_batch_size", 2)
    cnpjs = ["11111111000191", "22222222000191", "33333333000191"]
    route = _mock_search(
        [_crm_row(1, cnpjs[0]), _crm_row(2, cnpjs[1])], [_crm_row(3, cnpjs[2])], []
    )

    total = await make_service().backfill()

    assert total.imported == 3
    assert lookup.calls == cnpjs
    # Cada página reinicia o filtro a partir do último ID (sem `after`).
    cursors = [
        json.loads(c.request.content)["filterGroups"][0]["filters"][0]["value"]
        for c in route.calls
    ]
    assert cursors == ["0", "2", "3"]
    assert db.tables["crm_sync_state"][0]["last_crm_id"] == 100  # nunca anda pra trás


@respx.mock
async def test_backfill_sem_estado_previo_cria_a_marca_dagua(make_service, db):
    db.tables["crm_sync_state"].clear()
    _mock_search([_crm_row(7)], [])

    await make_service().backfill()

    assert db.tables["crm_sync_state"][0]["last_crm_id"] == 7


@respx.mock
async def test_run_forever_sobrevive_a_um_ciclo_com_erro_e_para_ao_cancelar(
    make_service, db
):
    sleeps = []

    async def sleep(seconds):
        sleeps.append(seconds)
        if len(sleeps) == 2:
            raise asyncio.CancelledError

    route = respx.post(SEARCH_URL).mock(
        side_effect=[
            httpx.Response(500, text="CRM fora do ar"),
            httpx.Response(200, json={"results": []}),
        ]
    )

    with pytest.raises(asyncio.CancelledError):
        await make_service(sleep=sleep).run_forever()

    assert route.call_count == 2  # o erro do 1º ciclo não parou o loop
    assert sleeps == [settings.crm_sync_interval_seconds] * 2


def test_build_company_row_replica_o_mapeamento_do_app():
    row = build_company_row(LOOKUP_DATA, CNPJ, -1.0, -2.0, "ROOFTOP")

    assert row["endereco_completo"] == "RUA DAS FLORES, 10 - CENTRO"
    assert row["razao_social"] == "ACME LTDA"
    assert row["nome_fantasia"] == "Acme"
    assert row["situacao"] == "ATIVA"
    assert row["cnae_principal"] == "Comércio"
    assert row["cep"] == "89201000"


def test_build_company_row_trata_data_e_telefone_ausentes():
    data = {**LOOKUP_DATA, "data_abertura": "00000000", "ddd_1": "", "tel_1": ""}

    row = build_company_row(data, CNPJ, 0.0, 0.0, "APPROXIMATE")

    assert row["data_abertura"] is None
    assert row["telefone_principal"] is None


def test_build_geocoding_address_inclui_cidade_e_uf():
    assert (
        build_geocoding_address(LOOKUP_DATA)
        == "RUA DAS FLORES, 10 - CENTRO, JOINVILLE - SC"
    )
