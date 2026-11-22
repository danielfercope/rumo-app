"""Catálogo de teses de recuperação tributária, lido do banco.

O conteúdo de cada tese (textos, base legal, situação jurídica, perguntas
para a visita e os CNAEs que a disparam) mora nas tabelas `teses_tributarias`,
`teses_tributarias_perguntas` e `teses_tributarias_cnaes`
(`db/schema/020_teses_tributarias.sql`). As condições ficam em `rules.py`,
ligadas à tese pelo `id`. Tese com `ativa = false` some do diagnóstico.

O catálogo é pequeno e muda pouco: fica em memória por `CACHE_TTL` e, se o
banco não responder, segue com a última cópia lida."""

import logging
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone

from ..postgrest_client import PostgrestClient

logger = logging.getLogger("uvicorn.error.tax_diagnosis")

CACHE_TTL = timedelta(minutes=5)

_SELECT = (
    "id,titulo,resumo,tributos,base_legal,situacao_juridica,em_discussao,"
    "como_abordar,atualizado_em,"
    "teses_tributarias_perguntas(ordem,texto,atualizado_em),"
    "teses_tributarias_cnaes(cnae,descricao,parcial,atualizado_em)"
)


class CatalogUnavailable(Exception):
    """O catálogo nunca foi lido e o banco não respondeu."""


@dataclass(frozen=True)
class CnaeTese:
    descricao: str
    parcial: bool = False


@dataclass(frozen=True)
class Tese:
    id: str
    titulo: str
    resumo: str
    tributos: tuple[str, ...]
    base_legal: str
    situacao_juridica: str
    como_abordar: str
    perguntas: tuple[str, ...] = ()
    em_discussao: bool = False
    cnaes: dict[str, CnaeTese] = field(default_factory=dict)


@dataclass(frozen=True)
class Catalogo:
    teses: dict[str, Tese]
    # maior `atualizado_em` das três tabelas: muda a cada edição do catálogo
    versao: str | None = None

    def get(self, tese_id: str) -> Tese | None:
        return self.teses.get(tese_id)

    @classmethod
    def from_rows(cls, rows: list[dict]) -> "Catalogo":
        """Linhas de `teses_tributarias` com perguntas e CNAEs embutidos
        (formato do PostgREST)."""
        teses: dict[str, Tese] = {}
        datas: list[str] = []
        for r in rows:
            perguntas = sorted(
                r.get("teses_tributarias_perguntas") or [], key=lambda p: p["ordem"]
            )
            cnaes = r.get("teses_tributarias_cnaes") or []
            datas += [x["atualizado_em"] for x in (r, *perguntas, *cnaes) if x.get("atualizado_em")]
            teses[r["id"]] = Tese(
                id=r["id"],
                titulo=r["titulo"],
                resumo=r["resumo"],
                tributos=tuple(r.get("tributos") or ()),
                base_legal=r["base_legal"],
                situacao_juridica=r["situacao_juridica"],
                como_abordar=r["como_abordar"],
                perguntas=tuple(p["texto"] for p in perguntas),
                em_discussao=bool(r.get("em_discussao")),
                cnaes={
                    c["cnae"].strip(): CnaeTese(c["descricao"], bool(c.get("parcial")))
                    for c in cnaes
                },
            )
        return cls(teses, max(datas) if datas else None)


class CatalogRepository:
    def __init__(
        self,
        db: PostgrestClient,
        *,
        clock: Callable[[], datetime] | None = None,
    ) -> None:
        self._db = db
        self._clock = clock or (lambda: datetime.now(timezone.utc))
        self._cached: Catalogo | None = None
        self._read_at: datetime | None = None

    async def get(self) -> Catalogo:
        now = self._clock()
        if self._cached and self._read_at and now - self._read_at < CACHE_TTL:
            return self._cached
        try:
            rows = await self._db.select(
                "teses_tributarias", {"select": _SELECT, "ativa": "eq.true"}
            )
        except Exception as exc:
            if self._cached:
                logger.warning("Catálogo de teses indisponível, usando a última cópia: %s", exc)
                return self._cached
            raise CatalogUnavailable(str(exc)) from exc
        self._cached, self._read_at = Catalogo.from_rows(rows), now
        return self._cached
