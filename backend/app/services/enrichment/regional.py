"""Fontes regionais (do município da empresa, não da empresa):
  - Comex Stat (MDIC): exportação e importação do município no último ano
    fechado, com principais produtos (SH4) e países. A Receita não publica
    comércio exterior por CNPJ; isto é o contexto econômico da cidade.
  - IBGE: população estimada, PIB e PIB per capita do município.

Chaveadas pelo código IBGE do município: a mesma resposta serve a todas as
empresas da cidade."""

import asyncio
from datetime import date

import httpx

from .base import SourceNotFound, SourceUnavailable, get_json, post_json

COMEX_URL = "https://api-comexstat.mdic.gov.br/cities?language=pt"
IBGE_URL = "https://servicodados.ibge.gov.br/api/v3/agregados"
TOP = 5


# ─── Comex Stat ─────────────────────────────────────────────────────────


async def comex(client: httpx.AsyncClient, ibge: int, today: date | None = None) -> dict:
    """Último ano fechado com dado publicado (o MDIC publica o ano por município
    só depois que ele termina)."""
    today = today or date.today()
    for year in (today.year - 1, today.year - 2):
        flows = await asyncio.gather(
            _comex_query(client, ibge, year, "export", "heading"),
            _comex_query(client, ibge, year, "export", "country"),
            _comex_query(client, ibge, year, "import", "heading"),
            _comex_query(client, ibge, year, "import", "country"),
        )
        exp_prod, exp_pais, imp_prod, imp_pais = flows
        if any(flows):
            return {
                "ano": year,
                "exportacao": _flow(exp_prod, exp_pais),
                "importacao": _flow(imp_prod, imp_pais),
            }
    raise SourceNotFound(f"sem comércio exterior registrado para {ibge}")


async def _comex_query(
    client: httpx.AsyncClient, ibge: int, year: int, flow: str, detail: str
) -> list[dict]:
    data = await post_json(
        client,
        COMEX_URL,
        {
            "flow": flow,
            "monthDetail": False,
            "period": {"from": f"{year}-01", "to": f"{year}-12"},
            "filters": [{"filter": "city", "values": [int(ibge)]}],
            "details": [detail],
            "metrics": ["metricFOB"],
        },
    )
    if not data.get("success", True):
        raise SourceUnavailable(data.get("message") or "Comex Stat recusou a consulta")
    return ((data.get("data") or {}).get("list")) or []


def _flow(produtos: list[dict], paises: list[dict]) -> dict:
    def fob(row) -> float:
        try:
            return float(row.get("metricFOB") or 0)
        except (TypeError, ValueError):
            return 0.0

    total = sum(fob(r) for r in produtos) or sum(fob(r) for r in paises)
    prods = sorted(produtos, key=fob, reverse=True)[:TOP]
    countries = sorted(paises, key=fob, reverse=True)[:TOP]
    return {
        "total_usd": round(total, 2),
        "produtos": [
            {
                "codigo": r.get("headingCode"),
                "nome": r.get("heading"),
                "usd": round(fob(r), 2),
                "participacao": round(fob(r) / total, 4) if total else 0,
            }
            for r in prods
        ],
        "paises": [
            {
                "nome": r.get("country"),
                "usd": round(fob(r), 2),
                "participacao": round(fob(r) / total, 4) if total else 0,
            }
            for r in countries
        ],
    }


# ─── IBGE ──────────────────────────────────────────────────────────────

POPULACAO = (6579, 9324)  # Estimativas de população: população residente
PIB = (5938, 37)  # PIB dos municípios: PIB a preços correntes (mil R$)


async def municipio(client: httpx.AsyncClient, ibge: int) -> dict:
    names: list[str] = []
    pop, pib = await asyncio.gather(
        _serie(client, *POPULACAO, ibge, period="-10", names=names),
        _serie(client, *PIB, ibge, names=names),
    )
    if not pop and not pib:
        raise SourceNotFound(f"IBGE sem dados para {ibge}")
    pop_year, pop_value = _latest(pop)
    pib_year, pib_value = _latest(pib)

    # PIB per capita com a população do ano do PIB; a estimativa não existe em
    # todo ano (ex.: ano de Censo), então usa o ano mais próximo disponível.
    per_capita = None
    if pib_value and pib_year and pop:
        nearest = min(pop, key=lambda y: (abs(int(y) - int(pib_year)), -int(y)))
        if pop[nearest]:
            per_capita = round(pib_value * 1000 / pop[nearest], 2)

    return {
        # nome oficial, com acento: "Jaraguá do Sul (SC)"
        "nome_ibge": names[0] if names else None,
        "populacao": {"valor": pop_value, "ano": pop_year} if pop_value else None,
        "pib": {"valor": pib_value * 1000, "ano": pib_year} if pib_value else None,
        "pib_per_capita": {"valor": per_capita, "ano": pib_year} if per_capita else None,
    }


async def _serie(
    client: httpx.AsyncClient,
    agregado: int,
    variavel: int,
    ibge: int,
    period: str = "-1",
    names: list[str] | None = None,
) -> dict[str, float]:
    data = await get_json(
        client,
        f"{IBGE_URL}/{agregado}/periodos/{period}/variaveis/{variavel}",
        params={"localidades": f"N6[{int(ibge)}]"},
    )
    out: dict[str, float] = {}
    for var in data or []:
        for res in var.get("resultados") or []:
            for serie in res.get("series") or []:
                nome = (serie.get("localidade") or {}).get("nome")
                if names is not None and nome and nome not in names:
                    names.append(nome)
                for year, value in (serie.get("serie") or {}).items():
                    try:
                        out[year] = float(value)
                    except (TypeError, ValueError):
                        continue  # "..." = dado não disponível
    return out


def _latest(serie: dict[str, float]) -> tuple[str | None, float | None]:
    if not serie:
        return None, None
    year = max(serie)
    return year, serie[year]
