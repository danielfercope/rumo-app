import asyncio
import uuid

import pytest

from app.errors import (
    ConnectionNotFoundError,
    InvalidCrmTokenError,
    InvalidMappingError,
    NotGroupAdminError,
    SyncInProgressError,
)
from app.services import carteira_connection_service as svc_module
from app.services.carteira_connection_service import CarteiraConnectionService
from app.services.carteira_sync_service import CarteiraSyncService
from app.services.crm_connector import CrmProperty
from tests.test_carteira_sync_service import (  # fixtures e fakes reaproveitados
    CNPJ_1,
    CNPJ_2,
    GROUP_A,
    GROUP_B,
    FakeConnector,
    FakeDb,
    FakeGeocoder,
    FakeLookup,
    cipher,
    db,
    lookup,
    rec,
)

__all__ = ["cipher", "db", "lookup"]  # fixtures importadas

UID_ADMIN = "uid-admin"
UID_MEMBER = "uid-member"
PROPS = [
    CrmProperty("cnpj", "CNPJ", "string"),
    CrmProperty("lifecyclestage", "Estágio", "enumeration"),
]
MAPEAMENTO = {
    "campo_cnpj": "cnpj",
    "campo_status": "lifecyclestage",
    "status": {"cliente": ["customer"], "perdido": ["other"]},
}


class FakeCrm(FakeConnector):
    def __init__(self, pages=None, props=None, invalid_token=False):
        super().__init__(pages)
        self.props = PROPS if props is None else props
        self.invalid_token = invalid_token

    async def validate(self):
        if self.invalid_token:
            raise InvalidCrmTokenError("token recusado")

    async def list_properties(self):
        return self.props


@pytest.fixture
def members(db):
    db.tables["group_members"] += [
        {"group_id": GROUP_A, "user_id": UID_ADMIN, "role": "admin"},
        {"group_id": GROUP_A, "user_id": UID_MEMBER, "role": "member"},
        {"group_id": GROUP_B, "user_id": "outro-admin", "role": "admin"},
    ]


@pytest.fixture
def make(db, lookup, cipher, members):
    def factory(connector, priority=None):
        async def no_sleep(_):
            pass

        def build(provedor, token):
            return connector

        sync = CarteiraSyncService(
            db, lookup, FakeGeocoder(), cipher, build,
            company_pause=0, sleep=no_sleep,
        )
        return CarteiraConnectionService(db, cipher, sync, build, priority=priority), sync

    return factory


async def _drain(service):
    await asyncio.gather(*service._tasks)


# ─── Autorização ────────────────────────────────────────────────────────


@pytest.mark.parametrize("uid", [UID_MEMBER, "desconhecido"])
async def test_so_admin_da_organizacao_pode_gerenciar(make, db, uid):
    service, _ = make(FakeCrm())
    calls = [
        service.validate(uid, GROUP_A, "hubspot", "tok"),
        service.preview(uid, GROUP_A, "hubspot", "tok", MAPEAMENTO),
        service.connect(uid, GROUP_A, "hubspot", "tok", MAPEAMENTO),
        service.sync_now(uid, GROUP_A),
        service.disconnect(uid, GROUP_A),
    ]
    for call in calls:
        with pytest.raises(NotGroupAdminError):
            await call
    assert db.writes == []


async def test_admin_de_outra_organizacao_nao_gerencia_esta(make):
    service, _ = make(FakeCrm())
    with pytest.raises(NotGroupAdminError):
        await service.validate("outro-admin", GROUP_A, "hubspot", "tok")


# ─── Validar e prévia ───────────────────────────────────────────────────


async def test_validar_devolve_as_propriedades_e_fecha_o_conector(make):
    connector = FakeCrm()
    service, _ = make(connector)

    props = await service.validate(UID_ADMIN, GROUP_A, "hubspot", "tok")

    assert [p.name for p in props] == ["cnpj", "lifecyclestage"]
    assert connector.closed


async def test_validar_token_recusado(make):
    connector = FakeCrm(invalid_token=True)
    service, _ = make(connector)

    with pytest.raises(InvalidCrmTokenError):
        await service.validate(UID_ADMIN, GROUP_A, "hubspot", "tok")
    assert connector.closed


async def test_previa_conta_por_status_e_nao_grava_nada(make, db):
    connector = FakeCrm(
        [
            [
                rec(1, CNPJ_1, "customer"),
                rec(2, CNPJ_2, "lead"),
                rec(3, "00000000000191", "other"),
                rec(4, "123", "lead"),
            ]
        ]
    )
    service, _ = make(connector)

    previa = await service.preview(UID_ADMIN, GROUP_A, "hubspot", "tok", MAPEAMENTO)

    assert previa == {
        "total_com_cnpj": 4,
        "validos": 3,
        "cnpj_invalido": 1,
        "por_status": {"cliente": 1, "lead": 1, "perdido": 1},
        "truncado": False,
    }
    assert db.writes == []  # prévia é sem estado: nem token, nem carteira
    assert connector.closed


async def test_previa_trunca_bases_grandes(make, monkeypatch):
    monkeypatch.setattr(svc_module, "PREVIEW_MAX_PAGES", 1)
    connector = FakeCrm([[rec(1, CNPJ_1)], [rec(2, CNPJ_2)]])
    service, _ = make(connector)

    previa = await service.preview(UID_ADMIN, GROUP_A, "hubspot", "tok", MAPEAMENTO)

    assert previa["truncado"] is True
    assert previa["validos"] == 1


async def test_mapeamento_com_propriedade_inexistente_e_recusado(make, db):
    service, _ = make(FakeCrm())
    bad = {**MAPEAMENTO, "campo_cnpj": "cnpj_errado"}

    with pytest.raises(InvalidMappingError, match="cnpj_errado"):
        await service.preview(UID_ADMIN, GROUP_A, "hubspot", "tok", bad)
    with pytest.raises(InvalidMappingError):
        await service.connect(UID_ADMIN, GROUP_A, "hubspot", "tok", bad)
    assert db.writes == []


# ─── Conectar ───────────────────────────────────────────────────────────


async def test_conectar_grava_token_cifrado_e_roda_a_carga_inicial(make, db, cipher):
    connector = FakeCrm([[rec(1, CNPJ_1, "customer"), rec(2, CNPJ_2, "lead")]])
    service, _ = make(connector)

    out = await service.connect(UID_ADMIN, GROUP_A, "hubspot", "pat-segredo", MAPEAMENTO)

    assert out["situacao"] == "pendente"
    (conexao,) = db.tables["crm_conexoes"]
    assert conexao["token_cifrado"] != "pat-segredo"
    assert "segredo" not in conexao["token_cifrado"]
    assert cipher.decrypt(conexao["token_cifrado"]) == "pat-segredo"
    assert conexao["mapeamento"] == MAPEAMENTO

    await _drain(service)  # a carga inicial roda em segundo plano
    assert conexao["situacao"] == "ativa"
    assert db.carteira(GROUP_A) == {CNPJ_1: "cliente", CNPJ_2: "lead"}


async def test_reconectar_substitui_a_conexao_e_zera_a_marca_dagua(make, db):
    service, _ = make(FakeCrm())  # CRM sem empresas: a marca d'água continua nula
    await service.connect(UID_ADMIN, GROUP_A, "hubspot", "tok-1", MAPEAMENTO)
    await _drain(service)
    db.tables["crm_conexoes"][0]["ultima_modificacao_crm"] = "2024-01-01T00:00:00+00:00"
    db.tables["crm_conexoes"][0]["situacao"] = "erro"

    await service.connect(UID_ADMIN, GROUP_A, "hubspot", "tok-2", MAPEAMENTO)

    assert len(db.tables["crm_conexoes"]) == 1  # uma conexão por organização
    assert db.tables["crm_conexoes"][0]["ultima_modificacao_crm"] is None
    await _drain(service)
    assert db.tables["crm_conexoes"][0]["situacao"] == "ativa"


async def test_conectar_durante_sincronizacao_e_recusado(make, db):
    service, sync = make(FakeCrm())
    await service.connect(UID_ADMIN, GROUP_A, "hubspot", "tok", MAPEAMENTO)
    await _drain(service)
    conexao_id = db.tables["crm_conexoes"][0]["id"]
    lock = asyncio.Lock()
    await lock.acquire()
    sync._locks[conexao_id] = lock  # simula uma sincronização em andamento

    with pytest.raises(SyncInProgressError):
        await service.connect(UID_ADMIN, GROUP_A, "hubspot", "tok", MAPEAMENTO)
    with pytest.raises(SyncInProgressError):
        await service.sync_now(UID_ADMIN, GROUP_A)
    with pytest.raises(SyncInProgressError):
        await service.disconnect(UID_ADMIN, GROUP_A)


# ─── Sincronizar agora ──────────────────────────────────────────────────


async def test_sincronizar_sem_conexao(make):
    service, _ = make(FakeCrm())
    with pytest.raises(ConnectionNotFoundError):
        await service.sync_now(UID_ADMIN, GROUP_A)


async def test_sincronizar_agora_dispara_em_segundo_plano(make, db):
    connector = FakeCrm()
    service, _ = make(connector)
    await service.connect(UID_ADMIN, GROUP_A, "hubspot", "tok", MAPEAMENTO)
    await _drain(service)
    connector.pages = [[rec(1, CNPJ_1, "customer")]]

    out = await service.sync_now(UID_ADMIN, GROUP_A)
    await _drain(service)

    assert out["conexao_id"] == db.tables["crm_conexoes"][0]["id"]
    assert db.carteira(GROUP_A) == {CNPJ_1: "cliente"}


# ─── Desconectar ────────────────────────────────────────────────────────


async def test_desconectar_sem_conexao(make):
    service, _ = make(FakeCrm())
    with pytest.raises(ConnectionNotFoundError):
        await service.disconnect(UID_ADMIN, GROUP_A)


async def _with_carteiras(service, db):
    await service.connect(UID_ADMIN, GROUP_A, "hubspot", "tok", MAPEAMENTO)
    await _drain(service)
    company = db.add_company("99999999000199")
    db.tables["carteira_empresas"] += [
        {"group_id": GROUP_A, "company_id": company["id"], "status": "cliente",
         "origem": "crm"},
        {"group_id": GROUP_A, "company_id": company["id"], "status": "cliente",
         "origem": "manual"},
        {"group_id": GROUP_B, "company_id": company["id"], "status": "lead",
         "origem": "crm"},
    ]


async def test_desconectar_mantem_a_carteira_por_padrao(make, db):
    service, _ = make(FakeCrm())
    await _with_carteiras(service, db)

    await service.disconnect(UID_ADMIN, GROUP_A)

    assert db.tables["crm_conexoes"] == []
    assert len(db.tables["carteira_empresas"]) == 3


async def test_desconectar_e_apagar_remove_so_o_que_veio_do_crm_da_organizacao(
    make, db
):
    service, _ = make(FakeCrm())
    await _with_carteiras(service, db)

    await service.disconnect(UID_ADMIN, GROUP_A, apagar_carteira=True)

    assert db.tables["crm_conexoes"] == []
    restantes = {(r["group_id"], r["origem"]) for r in db.tables["carteira_empresas"]}
    assert restantes == {(GROUP_A, "manual"), (GROUP_B, "crm")}


class _Priority:
    def __init__(self):
        self.cleared: list[str] = []

    async def clear(self, group_id):
        self.cleared.append(group_id)


async def test_apagar_a_carteira_apaga_tambem_a_prioridade_calculada(make, db):
    priority = _Priority()
    service, _ = make(FakeCrm(), priority)
    await _with_carteiras(service, db)

    await service.disconnect(UID_ADMIN, GROUP_A, apagar_carteira=True)

    assert priority.cleared == [GROUP_A]


async def test_desconectar_mantendo_a_carteira_mantem_a_prioridade(make, db):
    priority = _Priority()
    service, _ = make(FakeCrm(), priority)
    await _with_carteiras(service, db)

    await service.disconnect(UID_ADMIN, GROUP_A)

    assert priority.cleared == []
