"""Curva de aprendizado dos modelos de prioridade: quanto cada modelo acerta
conforme cresce o número de clientes conhecidos.

É o que decide, com dados, a partir de quantos clientes vale trocar de modelo
(os limiares de `choose_strategy`). Para cada tamanho de carteira, sorteia esse
nº de clientes do conjunto disponível, avalia cada modelo por validação
cruzada (`priority_score.evaluate`, a mesma pra todos) e repete com sorteios
diferentes pra tirar o ruído de "qual amostra caiu".

Funciona igual com dados sintéticos e com a carteira real de uma organização."""

import random
import statistics
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass

from . import logistic_score
from .priority_score import Company, evaluate
from .priority_score import fit as baseline_fit

Fitter = Callable[[Sequence[Company], Sequence[Company]], object]

DEFAULT_MODELS: dict[str, Fitter | None] = {
    "baseline": None,  # None = o fit do baseline em evaluate()
    "logistica": lambda train, universe: logistic_score.fit(train, universe),
}


@dataclass(frozen=True)
class Point:
    model: str
    n_clients: int
    auc_mean: float
    auc_std: float
    recall10_mean: float  # fração dos clientes escondidos que cai no top 10%
    lift10_mean: float  # recall@10% ÷ 10% (sorteio = 1,0)


def learning_curve(
    clients: Sequence[Company],
    candidates: Sequence[Company],
    sizes: Sequence[int],
    models: Mapping[str, Fitter | None] = DEFAULT_MODELS,
    repeats: int = 5,
    folds: int = 5,
    seed: int = 0,
) -> list[Point]:
    rng = random.Random(seed)
    clients = list(clients)
    points: list[Point] = []
    for size in sizes:
        if size > len(clients):
            raise ValueError(f"Pediu {size} clientes, só há {len(clients)}")
        samples = [rng.sample(clients, size) for _ in range(repeats)]
        for name, fitter in models.items():
            results = [
                evaluate(sample, candidates, folds=folds, seed=i, fitter=fitter)
                for i, sample in enumerate(samples)
            ]
            aucs = [r.auc for r in results]
            points.append(
                Point(
                    model=name,
                    n_clients=size,
                    auc_mean=statistics.fmean(aucs),
                    auc_std=statistics.pstdev(aucs),
                    recall10_mean=statistics.fmean(r.recall_at[0.1] for r in results),
                    lift10_mean=statistics.fmean(r.lift_at(0.1) for r in results),
                )
            )
    return points


def format_table(points: Sequence[Point]) -> str:
    """Tabela em Markdown: uma linha por nº de clientes, um bloco por modelo."""
    models = list(dict.fromkeys(p.model for p in points))
    sizes = sorted({p.n_clients for p in points})
    by = {(p.model, p.n_clients): p for p in points}
    header = "| clientes | " + " | ".join(f"{m} AUC (±dp)" for m in models) + " | " + " | ".join(
        f"{m} lift@10%" for m in models
    ) + " |"
    sep = "|" + "---|" * (1 + 2 * len(models))
    lines = [header, sep]
    for n in sizes:
        auc = " | ".join(
            f"{by[(m, n)].auc_mean:.3f} (±{by[(m, n)].auc_std:.3f})" for m in models
        )
        lift = " | ".join(f"{by[(m, n)].lift10_mean:.2f}x" for m in models)
        lines.append(f"| {n} | {auc} | {lift} |")
    return "\n".join(lines)


__all__ = ["Point", "learning_curve", "format_table", "baseline_fit"]
