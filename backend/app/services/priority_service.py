"""Prioridade dos leads de uma organização: calcula, guarda e serve.

Dois lados, de propósito separados:
  - `recalculate(group_id)` roda ao fim de cada sincronização que mudou a
    carteira (CarteiraSyncService). É o único que lê a base de empresas;
    grava o modelo (`prioridade_modelos`) e a lista ordenada de leads
    (`carteira_prioridade`).
  - `ranking(uid, group_id, limit)` é o que o endpoint chama a cada requisição
    e só LÊ o que já foi gravado: nenhuma varredura de `companies`.

A estratégia vem do tamanho da carteira (`choose_strategy`):
  - poucos clientes  → "interacao": mais interação no CRM, empate pelo registro
    mais antigo (não há o que aprender com tão poucos exemplos);
  - clientes suficientes → "perfil": parecença com o perfil dos clientes
    (priority_score.py), com motivos.
Os degraus seguintes (regressão logística, GBM) entram em `choose_strategy`."""

import asyncio
import logging
from datetime import datetime, timezone

from ..errors import NotGroupMemberError
from .cold_start_priority import rank_by_interaction
from .cold_start_priority import reason as interaction_reason
from .postgrest_client import PostgrestClient
from .priority_score import MIN_CLIENTS, fit, percentile_scores

logger = logging.getLogger("uvicorn.error.priority")

PAGE = 1000
# Teto de segurança da leitura da base inteira (companies é global); acima
# disso o perfil é calculado sobre os primeiros registros.
UNIVERSE_MAX_ROWS = 50_000
WRITE_CHUNK = 500
DEFAULT_LIMIT = 50
MAX_LIMIT = 200

COMPANY_COLUMNS = (
    "id,cnpj,razao_social,nome_fantasia,segmento,cnae_principal,"
    "natureza_juridica,porte,uf,municipio,data_abertura"
)

STRATEGY_INTERACTION = "interacao"
STRATEGY_PROFILE = "perfil"


def choose_strategy(n_clients: int) -> str:
    return STRATEGY_PROFILE if n_clients >= MIN_CLIENTS else STRATEGY_INTERACTION


class PriorityService:
    def __init__(self, db: PostgrestClient, clock=None) -> None:
        self._db = db
        self._clock = clock or (lambda: datetime.now(timezone.utc))

    # ─── Leitura (a cada requisição) ────────────────────────────────────

    async def ranking(
        self, uid: str, group_id: str, limit: int = DEFAULT_LIMIT
    ) -> dict:
        await self._require_member(uid, group_id)
        limit = max(1, min(limit, MAX_LIMIT))

        meta = await self._db.select(
            "prioridade_modelos",
            {
                "group_id": f"eq.{group_id}",
                "select": "estrategia,n_clientes,n_leads,calculado_em",
                "limit": "1",
            },
        )
        if not meta:
            # Ainda não houve cálculo (nova conexão ou nada mudou): o
            # resultado aparece depois da próxima sincronização.
            return {
                "estrategia": None,
                "n_clientes": 0,
                "n_leads": 0,
                "calculado_em": None,
                "minimo_clientes_perfil": MIN_CLIENTS,
                "itens": [],
            }

        rows = await self._db.select(
            "carteira_prioridade",
            {
                "group_id": f"eq.{group_id}",
                "select": "company_id,posicao,nota,motivos,"
                "companies(cnpj,razao_social,nome_fantasia,municipio,uf)",
                "order": "posicao.asc",
                "limit": str(limit),
            },
        )
        return {
            **meta[0],
            "minimo_clientes_perfil": MIN_CLIENTS,
            "itens": [self._item(r) for r in rows],
        }

    # ─── Cálculo (ao fim de cada sincronização que mudou a carteira) ────

    async def has_result(self, group_id: str) -> bool:
        rows = await self._db.select(
            "prioridade_modelos",
            {"group_id": f"eq.{group_id}", "select": "group_id", "limit": "1"},
        )
        return bool(rows)

    async def recalculate(self, group_id: str) -> None:
        carteira = await self._select_all(
            "carteira_empresas",
            {
                "group_id": f"eq.{group_id}",
                "select": "company_id,status,crm_criado_em,ultima_interacao_em,"
                "num_interacoes",
                "order": "company_id",
            },
        )
        clients = [r for r in carteira if r["status"] == "cliente"]
        leads = [r for r in carteira if r["status"] == "lead"]
        strategy = choose_strategy(len(clients))

        if strategy == STRATEGY_INTERACTION:
            rows, model_json = self._by_interaction(leads), None
        else:
            rows, model_json = await self._by_profile(clients, leads)

        now = self._clock().isoformat()
        for i in range(0, len(rows), WRITE_CHUNK):
            await self._db.upsert(
                "carteira_prioridade",
                [
                    {**r, "group_id": group_id, "calculado_em": now}
                    for r in rows[i : i + WRITE_CHUNK]
                ],
                on_conflict="group_id,company_id",
            )
        # O que não foi reescrito agora não é mais lead (virou cliente,
        # perdido ou saiu da carteira).
        await self._db.delete(
            "carteira_prioridade",
            {"group_id": f"eq.{group_id}", "calculado_em": f"lt.{now}"},
        )
        await self._db.upsert(
            "prioridade_modelos",
            [
                {
                    "group_id": group_id,
                    "estrategia": strategy,
                    "n_clientes": len(clients),
                    "n_leads": len(leads),
                    "modelo": model_json,
                    "calculado_em": now,
                }
            ],
            on_conflict="group_id",
        )

    async def clear(self, group_id: str) -> None:
        """Apaga o resultado (ex.: carteira importada foi removida)."""
        await self._db.delete("carteira_prioridade", {"group_id": f"eq.{group_id}"})
        await self._db.delete("prioridade_modelos", {"group_id": f"eq.{group_id}"})

    # ─── Estratégias ────────────────────────────────────────────────────

    def _by_interaction(self, leads: list[dict]) -> list[dict]:
        now = self._clock()
        return [
            {
                "company_id": row["company_id"],
                "posicao": i + 1,
                "nota": None,
                "motivos": [interaction_reason(row, now)],
            }
            for i, row in enumerate(rank_by_interaction(leads))
        ]

    async def _by_profile(
        self, clients: list[dict], leads: list[dict]
    ) -> tuple[list[dict], dict]:
        universe = await self._select_all(
            "companies",
            {"select": COMPANY_COLUMNS, "order": "id"},
            max_rows=UNIVERSE_MAX_ROWS,
        )
        by_id = {c["id"]: c for c in universe}
        client_companies = [
            by_id[r["company_id"]] for r in clients if r["company_id"] in by_id
        ]
        lead_companies = [
            by_id[r["company_id"]] for r in leads if r["company_id"] in by_id
        ]

        def compute():
            model = fit(client_companies, universe)
            scored = [(c, model.score(c)) for c in lead_companies]
            notas = percentile_scores([s.raw for _, s in scored])
            ranked = sorted(
                zip(scored, notas), key=lambda t: (-t[0][1].raw, t[0][0]["id"])
            )
            return model, [
                {
                    "company_id": company["id"],
                    "posicao": i + 1,
                    "nota": nota,
                    "motivos": [_describe(r) for r in scoring.top_reasons(3)],
                }
                for i, ((company, scoring), nota) in enumerate(ranked)
            ]

        # CPU puro sobre até dezenas de milhares de linhas: fora do laço de
        # eventos, senão a API inteira trava durante o recálculo.
        model, rows = await asyncio.to_thread(compute)
        return rows, model.to_json()

    # ─── Apoio ──────────────────────────────────────────────────────────

    @staticmethod
    def _item(row: dict) -> dict:
        company = row.get("companies") or {}
        return {
            "posicao": row["posicao"],
            "company_id": row["company_id"],
            "cnpj": company.get("cnpj"),
            "nome": company.get("nome_fantasia") or company.get("razao_social"),
            "municipio": company.get("municipio"),
            "uf": company.get("uf"),
            "nota": row["nota"],
            "motivos": row["motivos"],
        }

    async def _require_member(self, uid: str, group_id: str) -> None:
        rows = await self._db.select(
            "group_members",
            {"group_id": f"eq.{group_id}", "user_id": f"eq.{uid}", "select": "user_id"},
        )
        if not rows:
            raise NotGroupMemberError("Você não pertence a esta organização.")

    async def _select_all(
        self, table: str, params: dict[str, str], max_rows: int = 200_000
    ) -> list[dict]:
        rows: list[dict] = []
        while len(rows) < max_rows:
            page = await self._db.select(
                table, {**params, "limit": str(PAGE), "offset": str(len(rows))}
            )
            rows.extend(page)
            if len(page) < PAGE:
                break
        if len(rows) >= max_rows:
            logger.warning("Leitura de %s truncada em %s linhas", table, max_rows)
        return rows[:max_rows]


def _describe(reason) -> str:
    return (
        f"{reason.label}: {reason.value} "
        f"({reason.share_clients:.0%} dos seus clientes, "
        f"{reason.share_base:.0%} da base)"
    )
