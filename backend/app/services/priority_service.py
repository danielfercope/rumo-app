"""Prioridade dos leads de uma organização: calcula, guarda e serve.

Dois lados, de propósito separados:
  - `recalculate(group_id)` roda ao fim de cada sincronização que mudou a
    carteira (CarteiraSyncService). Lê SÓ a carteira da organização
    (`carteira_empresas` com os dados de cada empresa embutidos); grava o
    modelo (`prioridade_modelos`) e a lista ordenada de leads
    (`carteira_prioridade`).
  - `ranking(uid, group_id, limit)` é o que o endpoint chama a cada requisição
    e só LÊ o que já foi gravado: nenhuma varredura de `companies`.

A estratégia vem do tamanho da carteira (`choose_strategy`):
  - poucos clientes  → "interacao": mais interação no CRM, empate pelo registro
    mais antigo (não há o que aprender com tão poucos exemplos);
  - clientes suficientes → "perfil": parecença com o perfil dos clientes
    (priority_score.py), com motivos.

Isolamento: a carteira de uma organização nunca se mistura com a de outra.
O perfil compara os clientes com a PRÓPRIA carteira (clientes, leads e
perdidos da organização), e não com o catálogo global `companies`, que
contém empresas das outras organizações. Nenhuma contagem, nota ou motivo
depende do que outra organização tem.
Os degraus seguintes (regressão logística, GBM) entram em `choose_strategy`."""

import asyncio
import logging
from datetime import datetime, timezone

from ..errors import NotGroupMemberError
from .cold_start_priority import rank_by_interaction
from .cold_start_priority import reason as interaction_reason
from .postgrest_client import PostgrestClient
from .priority_score import (
    MIN_CLIENTS,
    MODEL_VERSION,
    PriorityModel,
    fit,
    percentile_scores,
)

logger = logging.getLogger("uvicorn.error.priority")

PAGE = 1000
WRITE_CHUNK = 500
DEFAULT_LIMIT = 50
MAX_LIMIT = 200
# Modo compacto (só id, posição e nota — o mapa precisa da carteira inteira).
MAX_LIMIT_COMPACT = 5000

COMPANY_COLUMNS = (
    "id,cnpj,razao_social,nome_fantasia,segmento,cnae_principal,"
    "natureza_juridica,porte,uf,municipio,data_abertura"
)

# Contribuição (média ponderada de log da razão de chances) a partir da qual um
# fator conta como "a favor" ou "contra"; entre os dois é neutro.
EFFECT_THRESHOLD = 0.1

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
        self,
        uid: str,
        group_id: str,
        limit: int = DEFAULT_LIMIT,
        compact: bool = False,
    ) -> dict:
        await self._require_member(uid, group_id)
        limit = max(1, min(limit, MAX_LIMIT_COMPACT if compact else MAX_LIMIT))

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
                "select": "company_id,posicao,nota"
                if compact
                else "company_id,posicao,nota,motivos,"
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

    async def explain(self, uid: str, group_id: str, company_id: str) -> dict:
        """Por que ESTE lead tem esta nota: todos os fatores, a favor e contra.

        Só lê o que já está gravado: a linha do lead, o modelo da organização
        (contagens) e a própria empresa. Reaplica o modelo a uma única empresa,
        o que é instantâneo e não varre `companies`."""
        await self._require_member(uid, group_id)
        rows = await self._db.select(
            "carteira_prioridade",
            {
                "group_id": f"eq.{group_id}",
                "company_id": f"eq.{company_id}",
                "select": "posicao,nota,motivos",
                "limit": "1",
            },
        )
        meta = await self._db.select(
            "prioridade_modelos",
            {
                "group_id": f"eq.{group_id}",
                "select": "estrategia,n_clientes,n_leads,modelo,calculado_em",
                "limit": "1",
            },
        )
        if not rows or not meta:
            return {"disponivel": False}
        row, meta = rows[0], meta[0]
        out: dict = {
            "disponivel": True,
            "estrategia": meta["estrategia"],
            "posicao": row["posicao"],
            "nota": row["nota"],
            "total_leads": meta["n_leads"],
            "n_clientes": meta["n_clientes"],
            "calculado_em": meta["calculado_em"],
            "motivos": row["motivos"],
            "fatores": [],
            "sem_dado": [],
            "sinais": None,
            "confiavel": True,
        }

        if meta["estrategia"] == STRATEGY_PROFILE and meta.get("modelo"):
            companies = await self._db.select(
                "companies",
                {"id": f"eq.{company_id}", "select": COMPANY_COLUMNS, "limit": "1"},
            )
            try:
                # Modelo de versão antiga (ex.: comparado com o catálogo
                # global) não é reaplicado: some até o próximo recálculo.
                model = PriorityModel.from_json(meta["modelo"])
            except ValueError:
                model = None
            if companies and model is not None:
                out["confiavel"] = model.reliable
                out["fatores"], out["sem_dado"] = _factors(
                    model, companies[0], meta["n_clientes"]
                )
        else:
            signals = await self._db.select(
                "carteira_empresas",
                {
                    "group_id": f"eq.{group_id}",
                    "company_id": f"eq.{company_id}",
                    "select": "crm_criado_em,ultima_interacao_em,num_interacoes",
                    "limit": "1",
                },
            )
            out["sinais"] = signals[0] if signals else None
        return out

    async def has_result(self, group_id: str) -> bool:
        """Há um resultado válido? Um perfil gravado por uma versão anterior do
        modelo (ex.: a que comparava com o catálogo global) não conta, pra o
        próximo ciclo recalcular mesmo sem mudança na carteira."""
        rows = await self._db.select(
            "prioridade_modelos",
            {"group_id": f"eq.{group_id}", "select": "estrategia,modelo", "limit": "1"},
        )
        if not rows:
            return False
        row = rows[0]
        if row.get("estrategia") != STRATEGY_PROFILE:
            return True
        return (row.get("modelo") or {}).get("version") == MODEL_VERSION

    async def recalculate(self, group_id: str) -> None:
        # Única leitura: a carteira DESTA organização, com os dados de cada
        # empresa embutidos. Nada de fora dela entra no cálculo.
        carteira = await self._select_all(
            "carteira_empresas",
            {
                "group_id": f"eq.{group_id}",
                "select": "company_id,status,crm_criado_em,ultima_interacao_em,"
                f"num_interacoes,companies({COMPANY_COLUMNS})",
                "order": "company_id",
            },
        )
        clients = [r for r in carteira if r["status"] == "cliente"]
        leads = [r for r in carteira if r["status"] == "lead"]
        strategy = choose_strategy(len(clients))

        if strategy == STRATEGY_INTERACTION:
            rows, model_json = self._by_interaction(leads), None
        else:
            rows, model_json = await self._by_profile(carteira)

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

    async def _by_profile(self, carteira: list[dict]) -> tuple[list[dict], dict]:
        # Universo = a carteira inteira da organização (clientes, leads e
        # perdidos); os clientes estão incluídos, como o `fit` espera.
        with_company = [r for r in carteira if r.get("companies")]
        universe = [r["companies"] for r in with_company]
        client_companies = [
            r["companies"] for r in with_company if r["status"] == "cliente"
        ]
        lead_companies = [r["companies"] for r in with_company if r["status"] == "lead"]

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

        # CPU puro sobre a carteira inteira: fora do laço de
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
            "motivos": row.get("motivos") or [],
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
        f"{reason.share_base:.0%} da sua carteira)"
    )


def _pretty(key: str, value: str) -> str:
    """Valor do fator pra exibição (o modelo guarda tudo em minúsculas)."""
    if key == "municipio" and "/" in value:
        uf, cidade = value.split("/", 1)
        return f"{cidade.title()} ({uf.upper()})"
    if key == "uf":
        return value.upper()
    return value[:1].upper() + value[1:]


def _factors(
    model: PriorityModel, company: dict, n_clients: int
) -> tuple[list[dict], list[str]]:
    """(fatores, características sem dado). Fatores do que mais ajuda ao que
    mais atrapalha; característica sem dado não pune nem premia."""
    scored = model.score(company)
    weight = {f.key: f.weight for f in model.features}
    fatores = []
    for r in scored.reasons:
        effect = (
            "favorece"
            if r.contribution > EFFECT_THRESHOLD
            else "desfavorece"
            if r.contribution < -EFFECT_THRESHOLD
            else "neutro"
        )
        fatores.append(
            {
                "chave": r.feature,
                "campo": r.label,
                "valor": _pretty(r.feature, r.value),
                "efeito": effect,
                "contribuicao": round(r.contribution, 3),
                "peso": weight.get(r.feature),
                "pct_clientes": round(r.share_clients, 4),
                "pct_base": round(r.share_base, 4),
                "clientes_com_valor": round(r.share_clients * n_clients),
                "vezes": round(r.share_clients / r.share_base, 2)
                if r.share_base
                else None,
            }
        )
    fatores.sort(key=lambda f: f["contribuicao"], reverse=True)
    sem_dado = [f.label for f in model.features if f.extract(company) is None]
    return fatores, sem_dado
