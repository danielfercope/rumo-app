"""Compras públicas: o que a empresa vendeu ao governo.

Fontes oficiais, sem chave:
  - Compras.gov.br (dados abertos): cadastro no SICAF e itens de licitação que
    a empresa ganhou (resultados publicados no PNCP, Lei 14.133 — União,
    estados e municípios que publicam no PNCP).
  - PNCP: dados da contratação (órgão, objeto, modalidade) das maiores vendas.

A consulta por fornecedor aceita no máximo 365 dias: lê os últimos 12 meses e
os 12 anteriores (pra mostrar a tendência)."""

import asyncio
from collections import defaultdict
from datetime import date, timedelta

import httpx

from .base import SourceNotFound, SourceUnavailable, blank_to_none, get_json

COMPRAS_URL = "https://dadosabertos.compras.gov.br"
RESULTADOS = COMPRAS_URL + "/modulo-contratacoes/3_consultarResultadoItensContratacoes_PNCP_14133"
FORNECEDOR = COMPRAS_URL + "/modulo-fornecedor/1_consultarFornecedor"
PNCP_COMPRA = "https://pncp.gov.br/api/consulta/v1/orgaos/{cnpj}/compras/{ano}/{seq}"
PNCP_LINK = "https://pncp.gov.br/app/editais/{cnpj}/{ano}/{seq}"

PAGE_SIZE = 500
MAX_PAGES = 4  # até 2.000 itens por período: o bastante pra somar e ranquear
TOP_CONTRATACOES = 5


async def fetch(client: httpx.AsyncClient, cnpj: str, today: date | None = None) -> dict:
    today = today or date.today()
    recent_from = today - timedelta(days=364)
    prev_to = recent_from - timedelta(days=1)
    prev_from = prev_to - timedelta(days=364)

    sicaf, recent, previous = await asyncio.gather(
        _sicaf(client, cnpj),
        _resultados(client, cnpj, recent_from, today),
        _resultados(client, cnpj, prev_from, prev_to),
        return_exceptions=True,
    )
    # Os itens ganhos são o coração da fonte: sem eles, a fonte está fora.
    if isinstance(recent, Exception):
        raise SourceUnavailable(str(recent))
    if isinstance(sicaf, Exception):
        sicaf = None
    if isinstance(previous, Exception):
        previous = None

    compras = _by_compra(recent)
    top = sorted(compras.values(), key=lambda c: c["valor"], reverse=True)[
        :TOP_CONTRATACOES
    ]
    details = await asyncio.gather(
        *(_detalhe(client, c["controle"]) for c in top), return_exceptions=True
    )
    contratacoes = []
    for c, d in zip(top, details):
        d = d if isinstance(d, dict) else {}
        contratacoes.append(
            {
                "orgao": d.get("orgao"),
                "orgao_cnpj": c["orgao_cnpj"],
                "uf": d.get("uf") or c["uf"],
                "municipio": d.get("municipio"),
                "objeto": d.get("objeto"),
                "modalidade": d.get("modalidade"),
                "valor": round(c["valor"], 2),
                "itens": c["itens"],
                "data": c["data"],
                "url": _link(c["controle"]),
            }
        )

    return {
        "periodo": {"de": recent_from.isoformat(), "ate": today.isoformat()},
        "sicaf": sicaf,
        "ultimos_12_meses": _summary(recent, compras),
        "12_meses_anteriores": None
        if previous is None
        else _summary(previous, _by_compra(previous)),
        "contratacoes": contratacoes,
    }


async def _sicaf(client: httpx.AsyncClient, cnpj: str) -> dict:
    data = await get_json(
        client, FORNECEDOR, params={"pagina": 1, "cnpj": cnpj, "ativo": "true"}
    )
    rows = data.get("resultado") or []
    if not rows:
        return {"cadastrado": False, "habilitado": False}
    row = rows[0]
    return {
        "cadastrado": True,
        "habilitado": bool(row.get("habilitadoLicitar")),
    }


async def _resultados(
    client: httpx.AsyncClient, cnpj: str, start: date, end: date
) -> list[dict]:
    items: list[dict] = []
    for page in range(1, MAX_PAGES + 1):
        try:
            data = await get_json(
                client,
                RESULTADOS,
                params={
                    "pagina": page,
                    "tamanhoPagina": PAGE_SIZE,
                    "niFornecedor": cnpj,
                    "dataResultadoPncpInicial": start.isoformat(),
                    "dataResultadoPncpFinal": end.isoformat(),
                },
            )
        except SourceNotFound:
            return items
        rows = data.get("resultado") or []
        # o filtro por fornecedor é do servidor; confere mesmo assim
        items.extend(r for r in rows if r.get("niFornecedor") == cnpj)
        if not data.get("paginasRestantes"):
            break
    return items


def _by_compra(items: list[dict]) -> dict[str, dict]:
    compras: dict[str, dict] = defaultdict(
        lambda: {"valor": 0.0, "itens": 0, "data": None}
    )
    for it in items:
        if it.get("dataCancelamentoPncp"):
            continue
        key = it.get("numeroControlePNCPCompra")
        if not key:
            continue
        c = compras[key]
        c["controle"] = key
        c["orgao_cnpj"] = it.get("orgaoEntidadeCnpj")
        c["uf"] = it.get("unidadeOrgaoUfSigla")
        c["valor"] += float(it.get("valorTotalHomologado") or 0)
        c["itens"] += 1
        d = (it.get("dataResultadoPncp") or "")[:10] or None
        if d and (c["data"] is None or d > c["data"]):
            c["data"] = d
    return dict(compras)


def _summary(items: list[dict], compras: dict[str, dict]) -> dict:
    return {
        "itens": sum(c["itens"] for c in compras.values()),
        "contratacoes": len(compras),
        "orgaos": len({c["orgao_cnpj"] for c in compras.values() if c["orgao_cnpj"]}),
        "valor": round(sum(c["valor"] for c in compras.values()), 2),
        "ufs": sorted({c["uf"] for c in compras.values() if c.get("uf")}),
    }


def _parse_controle(controle: str) -> tuple[str, str, int] | None:
    """"10727655000110-1-000168/2025" → (cnpj do órgão, ano, sequencial)."""
    try:
        cnpj, _, rest = controle.split("-", 2)
        seq, ano = rest.split("/")
        return cnpj, ano, int(seq)
    except ValueError:
        return None


def _link(controle: str) -> str | None:
    parts = _parse_controle(controle)
    if not parts:
        return None
    cnpj, ano, seq = parts
    return PNCP_LINK.format(cnpj=cnpj, ano=ano, seq=seq)


async def _detalhe(client: httpx.AsyncClient, controle: str) -> dict:
    parts = _parse_controle(controle)
    if not parts:
        return {}
    cnpj, ano, seq = parts
    d = await get_json(client, PNCP_COMPRA.format(cnpj=cnpj, ano=ano, seq=seq))
    orgao = d.get("orgaoEntidade") or {}
    unidade = d.get("unidadeOrgao") or {}
    objeto = blank_to_none(d.get("objetoCompra"))
    return {
        "orgao": blank_to_none(orgao.get("razaoSocial")),
        "uf": blank_to_none(unidade.get("ufSigla")),
        "municipio": blank_to_none(unidade.get("municipioNome")),
        "objeto": objeto[:280] if objeto else None,
        "modalidade": blank_to_none(d.get("modalidadeNome")),
    }
