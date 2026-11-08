"""Regra SINTÉTICA que decide quem é cliente, lead ou perdido.

Não existe carteira real: o status é inventado, mas por uma regra com lógica
comercial, pra que o teste tenha sinal a recuperar. Cenário: um representante
de insumos agrícolas baseado no SUL. A chance de uma revenda ser cliente dele
sobe com:
  - território: PR/RS/SC (forte) e vizinhos SP/MS/MG (leve);
  - porte: microempresa compra menos;
  - tempo de abertura: empresa já estabelecida compra mais;
e ~25% do resultado é sorteio puro (cliente nem sempre combina com o perfil).
Só usa atributos que o modelo de prioridade também enxerga.

O que isso valida: o ENCANAMENTO (conexão, sincronização, cálculo, tela). O AUC
obtido aqui mede quanto o modelo recupera a regra que escrevi — não o valor do
algoritmo numa carteira real. `ceiling_auc` dá o teto: o AUC de quem conhece a
probabilidade verdadeira."""

import math
import random
from collections.abc import Sequence
from dataclasses import dataclass
from datetime import date

from .enrich import Company

SUL = {"PR", "RS", "SC"}
VIZINHOS = {"SP", "MS", "MG"}

TARGET_CLIENT_RATE = 0.20
NOISE_SHARE = 0.25  # fração da probabilidade que é sorteio puro
# Intensidade do sinal. Com 1,0 o teto de AUC ficou ~0,66 (problema difícil
# demais pra um teste de encanamento); 2,0 leva o teto a ~0,76 sem tirar o ruído.
SIGNAL_SCALE = 2.0
LOST_SHARE_OF_NON_CLIENTS = 0.12


def _years(company: Company, today: date) -> float | None:
    if not company.inicio_atividade:
        return None
    try:
        opened = date.fromisoformat(company.inicio_atividade[:10])
    except ValueError:
        return None
    return (today - opened).days / 365.25


def score_logit(company: Company, today: date) -> float:
    """Parte "com lógica" da regra, antes da calibração e do ruído."""
    z = 0.0
    if company.uf in SUL:
        z += 1.4
    elif company.uf in VIZINHOS:
        z += 0.4

    z += {"MICRO EMPRESA": -0.5, "EMPRESA DE PEQUENO PORTE": 0.4}.get(
        company.porte, 0.4
    )

    years = _years(company, today)
    if years is not None:
        z += -0.8 if years < 2 else -0.2 if years < 5 else 0.3 if years < 10 else 0.6
    return z * SIGNAL_SCALE


def _sigmoid(x: float) -> float:
    return 1.0 / (1.0 + math.exp(-x))


def _mix(p: float, base: float) -> float:
    return (1 - NOISE_SHARE) * p + NOISE_SHARE * base


def calibrate_intercept(logits: Sequence[float], target: float) -> float:
    """Intercepto que faz a taxa ESPERADA de clientes (já com o ruído) ficar em
    `target`. Bisseção: a taxa cresce com o intercepto."""
    lo, hi = -10.0, 10.0
    for _ in range(60):
        mid = (lo + hi) / 2
        ps = [_sigmoid(z + mid) for z in logits]
        base = sum(ps) / len(ps)
        rate = sum(_mix(p, base) for p in ps) / len(ps)
        if rate < target:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2


@dataclass(frozen=True)
class Labeled:
    company: Company
    p_client: float  # probabilidade verdadeira (a que gerou o sorteio)
    status: str  # cliente | lead | perdido

    def to_json(self) -> dict:
        return {
            "company": self.company.to_json(),
            "p_client": self.p_client,
            "status": self.status,
        }

    @classmethod
    def from_json(cls, data: dict) -> "Labeled":
        return cls(Company.from_json(data["company"]), data["p_client"], data["status"])


def label(
    companies: Sequence[Company],
    *,
    seed: int = 42,
    today: date | None = None,
    client_rate: float = TARGET_CLIENT_RATE,
) -> list[Labeled]:
    today = today or date.today()
    rng = random.Random(seed)
    logits = [score_logit(c, today) for c in companies]
    intercept = calibrate_intercept(logits, client_rate)
    raw = [_sigmoid(z + intercept) for z in logits]
    base = sum(raw) / len(raw) if raw else 0.0

    out: list[Labeled] = []
    for company, p_raw in zip(companies, raw):
        p = _mix(p_raw, base)
        if rng.random() < p:
            status = "cliente"
        else:
            # perdido: quase ao acaso, com leve inclinação pra fora do território
            far = company.uf not in SUL | VIZINHOS
            status = "perdido" if rng.random() < LOST_SHARE_OF_NON_CLIENTS + (0.06 if far else 0.0) else "lead"
        out.append(Labeled(company, p, status))
    return out


def early_clients(labeled: Sequence[Labeled], n: int = 6) -> set[str]:
    """CNPJs dos n primeiros clientes (os de maior probabilidade): no estágio A
    só eles aparecem como cliente — o resto da carteira ainda é lead no CRM."""
    clients = sorted(
        (x for x in labeled if x.status == "cliente"),
        key=lambda x: (-x.p_client, x.company.cnpj),
    )
    return {x.company.cnpj for x in clients[:n]}


def status_at_stage(labeled: Labeled, stage: str, early: set[str]) -> str:
    """Estágio A: poucos clientes (testa a regra por interação). B: todos."""
    if stage == "B":
        return labeled.status
    if labeled.status == "cliente":
        return "cliente" if labeled.company.cnpj in early else "lead"
    return labeled.status


def ceiling_auc(labeled: Sequence[Labeled]) -> float:
    """AUC de quem ordena pela probabilidade verdadeira: o teto alcançável
    por qualquer modelo que veja só estes atributos."""
    from ...services.priority_score import _auc

    pos = [x.p_client for x in labeled if x.status == "cliente"]
    neg = [x.p_client for x in labeled if x.status != "cliente"]
    return _auc(pos, neg)


def summary(labeled: Sequence[Labeled]) -> dict:
    by_status: dict[str, int] = {}
    by_uf: dict[str, dict[str, int]] = {}
    for x in labeled:
        by_status[x.status] = by_status.get(x.status, 0) + 1
        bucket = by_uf.setdefault(x.company.uf, {"cliente": 0, "lead": 0, "perdido": 0})
        bucket[x.status] += 1
    return {"total": len(labeled), "por_status": by_status, "por_uf": by_uf}
