"""Lê os arquivos `Estabelecimentos*.zip` da base aberta da Receita Federal e
devolve as matrizes ativas dos CNAEs do segmento.

Lê direto de dentro do zip, em fluxo (os CSVs descompactados passam de 1 GB).
Layout (metadados oficiais): separado por `;`, latin-1; colunas usadas:
  0-2 CNPJ (básico, ordem, DV) · 3 matriz(1)/filial(2) · 5 situação (02 = ativa)
  10 data de início da atividade (AAAAMMDD) · 11 CNAE principal · 19 UF · 20 município."""

import csv
import io
import random
import zipfile
from collections import defaultdict
from collections.abc import Callable, Iterable, Sequence
from dataclasses import dataclass

# Comércio atacadista de insumos agropecuários (tabela oficial de CNAEs).
AGRO_CNAES = frozenset({"4683400", "4692300", "4623106", "4623109"})


@dataclass(frozen=True)
class Candidate:
    cnpj: str  # 14 dígitos
    cnae: str
    uf: str
    municipio_codigo: str
    inicio_atividade: str  # AAAAMMDD

    @property
    def ano(self) -> int | None:
        try:
            return int(self.inicio_atividade[:4])
        except ValueError:
            return None


def read_candidates(
    zip_path: str, cnaes: Iterable[str] = AGRO_CNAES
) -> list[Candidate]:
    cnaes = set(cnaes)
    out: list[Candidate] = []
    with zipfile.ZipFile(zip_path) as z:
        with z.open(z.namelist()[0]) as raw:
            reader = csv.reader(
                io.TextIOWrapper(raw, encoding="latin-1", newline=""), delimiter=";"
            )
            for row in reader:
                if len(row) < 21:
                    continue
                # só matriz (filiais repetiriam a mesma empresa) e só ativa
                if row[3] != "1" or row[5] != "02" or row[11] not in cnaes:
                    continue
                out.append(
                    Candidate(
                        cnpj=row[0] + row[1] + row[2],
                        cnae=row[11],
                        uf=row[19],
                        municipio_codigo=row[20],
                        inicio_atividade=row[10],
                    )
                )
    return out


def read_municipios(zip_path: str) -> dict[str, str]:
    """código do município (o mesmo de Estabelecimentos) → nome."""
    with zipfile.ZipFile(zip_path) as z:
        with z.open(z.namelist()[0]) as raw:
            reader = csv.reader(
                io.TextIOWrapper(raw, encoding="latin-1", newline=""), delimiter=";"
            )
            return {row[0]: row[1] for row in reader if len(row) >= 2}


def decade(year: int | None) -> str:
    """Faixa de abertura. Os arquivos da Receita são repartidos por faixa de CNPJ,
    que correlaciona com a idade da empresa; amostrar por faixa compensa o viés
    de usar só alguns arquivos."""
    if year is None:
        return "?"
    if year >= 2020:
        return "2020+"
    if year >= 2010:
        return "2010s"
    if year >= 2000:
        return "2000s"
    return "<2000"


# Fatia de cada faixa na amostra final: sem isso, os arquivos baixados trariam
# mais de 70% de empresas dos anos 2020.
DEFAULT_DECADE_SHARE = {"2020+": 0.30, "2010s": 0.30, "2000s": 0.20, "<2000": 0.20}


def stratified_sample(
    items: Sequence,
    n: int,
    key: Callable,
    share: dict[str, float] = DEFAULT_DECADE_SHARE,
    seed: int = 0,
) -> list:
    """Sorteia `n` itens respeitando a fatia de cada estrato. Estrato com menos
    itens que a cota entrega todos, e a sobra é redistribuída entre os demais
    (em vez de a amostra sair menor que o pedido)."""
    rng = random.Random(seed)
    groups: dict[str, list] = defaultdict(list)
    for item in items:
        groups[key(item)].append(item)
    for g in groups.values():
        g.sort(key=repr)  # ordem estável antes do sorteio: reprodutível
        rng.shuffle(g)

    n = min(n, len(items))
    taken: dict[str, int] = {}
    active = {k: share.get(k, 0.0) for k in groups if share.get(k, 0.0) > 0}
    remaining = n
    while remaining > 0 and active:
        total = sum(active.values())
        pool = remaining  # as cotas da rodada saem do mesmo total, não de um que encolhe
        progressed = False
        for k in list(active):
            quota = max(1, round(pool * active[k] / total))
            room = len(groups[k]) - taken.get(k, 0)
            give = min(quota, room, remaining)
            if give > 0:
                taken[k] = taken.get(k, 0) + give
                remaining -= give
                progressed = True
            if len(groups[k]) - taken.get(k, 0) == 0:
                del active[k]
            if remaining == 0:
                break
        if not progressed:
            break
    # estratos sem fatia definida só entram se ainda faltar
    if remaining > 0:
        for k, g in groups.items():
            room = len(g) - taken.get(k, 0)
            give = min(room, remaining)
            if give > 0:
                taken[k] = taken.get(k, 0) + give
                remaining -= give

    out: list = []
    for k, count in taken.items():
        out.extend(groups[k][:count])
    return out
