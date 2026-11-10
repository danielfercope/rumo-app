"""Enriquecimento por CNPJ na BrasilAPI (porte, natureza jurídica, razão social)
e filtro de quem NÃO deve ir pro HubSpot.

Excluídos: empresário individual e MEI — a razão social deles costuma ser o
nome de uma pessoa física (com parte do CPF), e esse seed sobe dados a uma
conta de CRM. Telefone e e-mail das empresas também nunca são lidos pra cá."""

import asyncio
import json
import os
from collections.abc import Awaitable, Callable
from dataclasses import dataclass

import httpx

BASE_URL = "https://brasilapi.com.br/api/cnpj/v1"
NATUREZA_EMPRESARIO_INDIVIDUAL = 2135


@dataclass(frozen=True)
class Company:
    cnpj: str
    razao_social: str
    nome_fantasia: str | None
    porte: str  # MICRO EMPRESA | EMPRESA DE PEQUENO PORTE | DEMAIS
    natureza_juridica: str
    cnae_descricao: str | None
    uf: str
    municipio: str
    inicio_atividade: str | None  # AAAA-MM-DD

    def to_json(self) -> dict:
        return self.__dict__.copy()

    @classmethod
    def from_json(cls, data: dict) -> "Company":
        return cls(**data)


def exclusion_reason(raw: dict) -> str | None:
    """Motivo pelo qual a empresa NÃO entra no seed (ou None se pode entrar)."""
    if (raw.get("descricao_situacao_cadastral") or "").upper() != "ATIVA":
        return "inativa"
    if raw.get("codigo_natureza_juridica") == NATUREZA_EMPRESARIO_INDIVIDUAL:
        return "empresario_individual"
    if raw.get("opcao_pelo_mei"):
        return "mei"
    if not raw.get("razao_social") or not raw.get("uf") or not raw.get("municipio"):
        return "dados_incompletos"
    if raw.get("uf") == "EX":
        return "exterior"  # endereço fora do país: não dá pra geocodificar
    return None


def to_company(raw: dict) -> Company:
    return Company(
        cnpj=raw["cnpj"],
        razao_social=raw["razao_social"],
        nome_fantasia=raw.get("nome_fantasia") or None,
        porte=(raw.get("porte") or "DEMAIS").upper(),
        natureza_juridica=raw.get("natureza_juridica") or "",
        cnae_descricao=raw.get("cnae_fiscal_descricao"),
        uf=raw["uf"],
        municipio=raw["municipio"],
        inicio_atividade=raw.get("data_inicio_atividade"),
    )


class Cache:
    """Respostas da BrasilAPI em disco (JSON por linha): se o script cair no
    meio das centenas de consultas, a próxima execução retoma de onde parou."""

    def __init__(self, path: str | None) -> None:
        self.path = path
        self.data: dict[str, dict | None] = {}
        if path and os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                for line in f:
                    row = json.loads(line)
                    self.data[row["cnpj"]] = row["raw"]

    def put(self, cnpj: str, raw: dict | None) -> None:
        self.data[cnpj] = raw
        if self.path:
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(json.dumps({"cnpj": cnpj, "raw": raw}, ensure_ascii=False) + "\n")


async def fetch_raw(
    client: httpx.AsyncClient,
    cnpj: str,
    sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    retries: int = 4,
) -> dict | None:
    """Uma consulta, com espera ao ser limitado (429). None = CNPJ não achado."""
    for attempt in range(retries + 1):
        response = await client.get(f"/{cnpj}")
        if response.status_code == 404:
            return None
        if response.status_code == 429 or response.status_code >= 500:
            await sleep(min(30.0, 2.0 * 2**attempt))
            continue
        response.raise_for_status()
        return response.json()
    raise RuntimeError(f"BrasilAPI indisponível para {cnpj} após {retries + 1} tentativas")


async def enrich(
    cnpjs: list[str],
    wanted: int,
    cache: Cache,
    *,
    client: httpx.AsyncClient | None = None,
    pause: float = 0.4,
    sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    on_progress: Callable[[int, int, int], None] | None = None,
) -> tuple[list[Company], dict[str, int]]:
    """Consulta CNPJ por CNPJ até juntar `wanted` empresas aceitas (ou acabar a
    lista). Devolve as aceitas e o motivo de cada exclusão."""
    own = client is None
    client = client or httpx.AsyncClient(base_url=BASE_URL, timeout=15.0)
    accepted: list[Company] = []
    excluded: dict[str, int] = {}
    try:
        for i, cnpj in enumerate(cnpjs, 1):
            if len(accepted) >= wanted:
                break
            if cnpj in cache.data:
                raw = cache.data[cnpj]
            else:
                raw = await fetch_raw(client, cnpj, sleep)
                cache.put(cnpj, raw)
                await sleep(pause)
            reason = "nao_encontrado" if raw is None else exclusion_reason(raw)
            if reason:
                excluded[reason] = excluded.get(reason, 0) + 1
            else:
                accepted.append(to_company(raw))
            if on_progress:
                on_progress(i, len(accepted), len(cnpjs))
    finally:
        if own:
            await client.aclose()
    return accepted, excluded
