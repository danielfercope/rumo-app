import pytest

from app.errors import CompanyNotInPortfolioError, NotGroupMemberError
from app.services.access_service import AccessService


class FakeDb:
    """O que o AccessService usa do PostgREST: group_members e a carteira com
    embed (inner) de companies filtrado por CNPJ."""

    def __init__(self):
        self.members = [
            {"group_id": "g1", "user_id": "u1"},
            {"group_id": "g2", "user_id": "u2"},
        ]
        self.companies = {"c1": "11111111000111", "c2": "22222222000122"}
        self.carteira = [
            {"group_id": "g1", "company_id": "c1"},
            {"group_id": "g2", "company_id": "c2"},
        ]

    @staticmethod
    def _eq(params, key):
        value = params.get(key)
        return value[3:] if value else None

    async def select(self, table, params):
        if table == "group_members":
            g, u = self._eq(params, "group_id"), self._eq(params, "user_id")
            rows = [
                r for r in self.members
                if (g is None or r["group_id"] == g) and (u is None or r["user_id"] == u)
            ]
            return rows[: int(params.get("limit", len(rows)))]
        assert table == "carteira_empresas"
        assert "companies!inner" in params["select"], "o filtro por CNPJ exige inner"
        g, cnpj = self._eq(params, "group_id"), self._eq(params, "companies.cnpj")
        return [
            r for r in self.carteira
            if r["group_id"] == g and self.companies[r["company_id"]] == cnpj
        ]


@pytest.fixture
def access():
    return AccessService(FakeDb())


async def test_membro_passa(access):
    await access.require_member("u1", "g1")


async def test_nao_membro_e_barrado(access):
    with pytest.raises(NotGroupMemberError):
        await access.require_member("u1", "g2")
    with pytest.raises(NotGroupMemberError):
        await access.require_member("desconhecido", "g1")


async def test_qualquer_organizacao(access):
    await access.require_any_organization("u2")
    with pytest.raises(NotGroupMemberError, match="Entre em uma organização"):
        await access.require_any_organization("sem-organizacao")


async def test_cnpj_da_carteira_passa_com_ou_sem_mascara(access):
    await access.require_cnpj_in_portfolio("g1", "11111111000111")
    await access.require_cnpj_in_portfolio("g1", "11.111.111/0001-11")


async def test_cnpj_de_outra_organizacao_e_barrado_sem_revelar_que_existe(access):
    with pytest.raises(CompanyNotInPortfolioError) as fora:
        await access.require_cnpj_in_portfolio("g1", "22222222000122")  # só g2 tem
    with pytest.raises(CompanyNotInPortfolioError) as inexistente:
        await access.require_cnpj_in_portfolio("g1", "99999999000199")  # ninguém tem
    assert str(fora.value) == str(inexistente.value), "mesma resposta: não é oráculo"


@pytest.mark.parametrize("cnpj", ["", None, "abc"])
async def test_cnpj_vazio_ou_invalido_e_barrado(access, cnpj):
    with pytest.raises(CompanyNotInPortfolioError):
        await access.require_cnpj_in_portfolio("g1", cnpj)
