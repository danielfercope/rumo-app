"""Prioridade quando a organização ainda tem poucos clientes (< MIN_CLIENTS):
não há o que aprender, então a ordem vem direto do histórico no CRM.

Regra: mais interação primeiro; em empate, o registro mais antigo no CRM.
Função pura sobre as linhas da carteira (`num_interacoes`, `crm_criado_em`)."""

from collections.abc import Mapping, Sequence
from datetime import datetime

Row = Mapping[str, object]

_FAR_FUTURE = float("inf")


def _created_at(row: Row) -> float:
    value = row.get("crm_criado_em")
    if not value:
        return _FAR_FUTURE  # sem data: depois de todos os que têm
    return datetime.fromisoformat(str(value)).timestamp()


def _interactions(row: Row) -> int:
    value = row.get("num_interacoes")
    return int(value) if isinstance(value, (int, float)) else 0


def rank_by_interaction(rows: Sequence[Row]) -> list[Row]:
    """Mais interação primeiro; empate pelo mais antigo no CRM; quem não tem
    nem data nem interação fica por último. Estável: o que empata em tudo
    mantém a ordem de entrada."""
    return sorted(rows, key=lambda r: (-_interactions(r), _created_at(r)))


def reason(row: Row, today: datetime) -> str:
    """Frase curta que explica a posição, pra tela."""
    n = _interactions(row)
    created = _created_at(row)
    parts = [f"{n} interações" if n != 1 else "1 interação"]
    if created != _FAR_FUTURE:
        days = int((today.timestamp() - created) // 86400)
        parts.append(f"no CRM há {days} dias")
    return " · ".join(parts)
