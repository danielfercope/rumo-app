"""Diagnóstico tributário de uma empresa da carteira.

Confere o acesso (membro, organização com CRM, CNPJ na carteira) uma vez,
lê as fontes `receita` e `compras` do enriquecimento (com o cache delas) e o
catálogo de teses do banco, e aplica as regras. Nada é gravado: o cálculo é
barato e as fontes já estão em cache.

Resposta:
    {"status": ok | vazio | indisponivel, "versao", "principal", "outras",
     "bloqueio", "fontes_faltando", "aviso", "atualizado_em"}"""

import asyncio
import logging
from collections.abc import Callable
from datetime import date, datetime, timedelta, timezone

from ..access_service import AccessService
from ..enrichment.base import digits
from ..enrichment.service import EnrichmentService
from .catalog import CatalogRepository, CatalogUnavailable
from .rules import diagnose
from .signals import extract

logger = logging.getLogger("uvicorn.error.tax_diagnosis")

BRT = timezone(timedelta(hours=-3))

AVISO = (
    "Hipótese a partir de dados públicos (Receita Federal e compras públicas). "
    "Não substitui a análise das apurações da empresa."
)


class TaxDiagnosisService:
    def __init__(
        self,
        access: AccessService,
        enrichment: EnrichmentService,
        catalog: CatalogRepository,
        *,
        today: Callable[[], date] | None = None,
    ) -> None:
        self._access = access
        self._enrichment = enrichment
        self._catalog = catalog
        self._today = today or (lambda: datetime.now(BRT).date())

    async def get(self, uid: str, group_id: str, cnpj: str) -> dict:
        await self._access.require_member(uid, group_id)
        await self._access.require_crm(group_id)
        await self._access.require_cnpj_in_portfolio(group_id, cnpj)
        cnpj = digits(cnpj)

        receita, compras, catalogo = await asyncio.gather(
            self._enrichment.fetch_cached("receita", cnpj),
            self._enrichment.fetch_cached("compras", cnpj),
            self._catalog.get(),
            return_exceptions=True,
        )
        if isinstance(catalogo, BaseException):
            if not isinstance(catalogo, CatalogUnavailable):
                logger.exception("Falha ao ler o catálogo de teses", exc_info=catalogo)
            return self._vazio("indisponivel", None)
        if isinstance(receita, BaseException):
            logger.warning("Receita indisponível no diagnóstico de %s: %r", cnpj, receita)
            return self._vazio("indisponivel", catalogo.versao)
        if receita.get("status") != "ok" or not receita.get("dados"):
            status = "indisponivel" if receita.get("status") == "indisponivel" else "vazio"
            return self._vazio(status, catalogo.versao)

        faltando = []
        compras_dados = None
        if isinstance(compras, BaseException) or compras.get("status") not in ("ok", "vazio"):
            faltando.append("compras")
        elif compras.get("status") == "ok":
            compras_dados = compras.get("dados")
        else:  # sem vendas ao governo: zero, não "sem dado"
            compras_dados = {}

        signals = extract(receita["dados"], compras_dados, self._today())
        return {
            "status": "ok",
            "versao": catalogo.versao,
            **diagnose(signals, catalogo),
            "fontes_faltando": faltando,
            "aviso": AVISO,
            "atualizado_em": receita.get("atualizado_em"),
        }

    @staticmethod
    def _vazio(status: str, versao: str | None) -> dict:
        return {
            "status": status,
            "versao": versao,
            "principal": None,
            "outras": [],
            "bloqueio": None,
            "fontes_faltando": ["receita"],
            "aviso": AVISO,
            "atualizado_em": None,
        }
