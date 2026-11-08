"""Score de prioridade por regressão logística (segundo degrau do seletor).

Mesma pergunta do baseline (`priority_score`) — "quão parecida com os
clientes é esta empresa?" — e mesma interface (`fit`/`score`), mas aqui os
pesos de cada característica são APRENDIDOS: uma regressão logística de
"cliente" contra "base inteira" (positivo-não-rotulado: o rótulo 0 é "não sei
se é cliente", e como a probabilidade de ser rotulado é proporcional à de ser
cliente, o ranking continua válido).

Diferença que importa em relação ao baseline: o naive Bayes soma o efeito de
cada característica como se fossem independentes, então duas características
redundantes (CNAE e segmento, que dizem quase a mesma coisa) contam em dobro.
A logística ajusta os pesos em conjunto e reparte o crédito entre elas.

O ajuste usa numpy e um L-BFGS próprio (o problema é convexo, então tem ótimo
único e o critério de parada é real: gradiente ~ 0). Sem scipy, de propósito:
uma dependência pesada a menos na imagem do Backend. É CPU puro: quem chama
de código assíncrono deve usar `to_thread`."""

import random
from collections import Counter
from collections.abc import Mapping, Sequence
from dataclasses import dataclass

import numpy as np

from .priority_score import DEFAULT_FEATURES, Company, Feature, Reason, Scored

MODEL_VERSION = 1

# Regularização L2 no estilo scikit-learn: C é o INVERSO da força (C menor =
# mais conservador). Sem ela, um valor visto em 1 cliente ganha peso enorme.
# Cada amostra pesa 1 (sem balancear as classes): é o que mantém a contagem de
# evidência — 1 cliente num valor pesa menos que 20 —, que o balanceamento
# apagaria por normalizar a massa total de positivos.
# 0,1 foi o melhor entre 0,1/0,3/1/3 na curva de aprendizado sintética
# (model_comparison.learning_curve), em todos os tamanhos de carteira. Foi
# escolhido nos mesmos dados em que se mede, então é otimista: com a carteira
# real, escolher C por validação cruzada interna.
DEFAULT_C = 0.1
# Negativos (base) usados no ajuste. Subamostrar a base mantém o ajuste em
# segundos sem mudar o ranking; as contagens da explicação usam a base toda.
DEFAULT_MAX_NEGATIVES = 5000
MAX_ITERATIONS = 500
GRADIENT_TOL = 1e-6  # norma-infinito do gradiente
LBFGS_MEMORY = 10


def _active(
    company: Company, features: Sequence[Feature]
) -> list[tuple[str, str, float]]:
    """(característica, valor, peso do julgamento) das que a empresa tem."""
    out = []
    for feature in features:
        value = feature.extract(company)
        if value is not None:
            out.append((feature.key, value, feature.weight))
    return out


@dataclass
class LogisticModel:
    features: tuple[Feature, ...]
    bias: float
    weights: dict[tuple[str, str], float]
    n_clients: int
    # Só pra explicação ("X% dos seus clientes, Y% da base").
    clients_counts: dict[str, Counter]
    base_counts: dict[str, Counter]
    n_clients_by_feature: dict[str, int]
    n_base_by_feature: dict[str, int]
    converged: bool = True
    n_iter: int = 0

    @property
    def reliable(self) -> bool:
        from .priority_score import MIN_CLIENTS

        return self.n_clients >= MIN_CLIENTS

    def score(self, company: Company) -> Scored:
        z = self.bias
        reasons: list[Reason] = []
        for key, value, _ in _active(company, self.features):
            w = self.weights.get((key, value))
            if w is None:
                continue  # valor nunca visto no ajuste: sem evidência
            z += w
            label = next(f.label for f in self.features if f.key == key)
            n_c = self.n_clients_by_feature.get(key, 0)
            n_b = self.n_base_by_feature.get(key, 0)
            reasons.append(
                Reason(
                    feature=key,
                    label=label,
                    value=value,
                    contribution=w,
                    share_clients=self.clients_counts[key][value] / n_c if n_c else 0.0,
                    share_base=self.base_counts[key][value] / n_b if n_b else 0.0,
                )
            )
        return Scored(raw=z, reasons=tuple(reasons))

    def to_json(self) -> dict:
        return {
            "version": MODEL_VERSION,
            "kind": "logistic",
            "bias": self.bias,
            "n_clients": self.n_clients,
            "weights": [[k, v, w] for (k, v), w in self.weights.items()],
            "clients_counts": {k: dict(c) for k, c in self.clients_counts.items()},
            "base_counts": {k: dict(c) for k, c in self.base_counts.items()},
            "n_clients_by_feature": self.n_clients_by_feature,
            "n_base_by_feature": self.n_base_by_feature,
        }

    @classmethod
    def from_json(
        cls, data: Mapping, features: Sequence[Feature] = DEFAULT_FEATURES
    ) -> "LogisticModel":
        if data.get("version") != MODEL_VERSION or data.get("kind") != "logistic":
            raise ValueError("Modelo logístico de versão desconhecida")
        return cls(
            features=tuple(features),
            bias=data["bias"],
            weights={(k, v): w for k, v, w in data["weights"]},
            n_clients=data["n_clients"],
            clients_counts={k: Counter(c) for k, c in data["clients_counts"].items()},
            base_counts={k: Counter(c) for k, c in data["base_counts"].items()},
            n_clients_by_feature=data["n_clients_by_feature"],
            n_base_by_feature=data["n_base_by_feature"],
        )


def _objective(theta, rowid, idx, scale, y, n, l2):
    """Perda logística média + (l2/2)·Σw². theta = [bias, w...]. Devolve
    (valor, gradiente)."""
    bias, w = theta[0], theta[1:]
    z = bias + np.bincount(rowid, weights=(w * scale)[idx], minlength=n)
    # logaddexp(0, z) = log(1 + e^z) sem estourar
    loss = np.mean(np.logaddexp(0.0, z) - y * z) + 0.5 * l2 * float(w @ w)
    err = (1.0 / (1.0 + np.exp(-np.clip(z, -500, 500))) - y) / n
    grad_w = np.bincount(idx, weights=err[rowid] * scale[idx], minlength=len(w))
    grad = np.concatenate(([err.sum()], grad_w + l2 * w))
    return loss, grad


def _lbfgs(fun, x0, max_iter=MAX_ITERATIONS, tol=GRADIENT_TOL, m=LBFGS_MEMORY):
    """L-BFGS com busca linear por retrocesso (Armijo). Convexo: sempre
    converge pro ótimo único. Devolve (x, convergiu, iterações)."""
    x = x0.copy()
    f, g = fun(x)
    s_hist: list[np.ndarray] = []
    y_hist: list[np.ndarray] = []
    for it in range(max_iter):
        if np.max(np.abs(g)) < tol:
            return x, True, it
        # recursão de duas voltas: direção ≈ -H·g
        q = g.copy()
        alphas = []
        for s_i, y_i in zip(reversed(s_hist), reversed(y_hist)):
            rho = 1.0 / (y_i @ s_i)
            a = rho * (s_i @ q)
            alphas.append((a, rho, s_i, y_i))
            q -= a * y_i
        if s_hist:
            q *= (s_hist[-1] @ y_hist[-1]) / (y_hist[-1] @ y_hist[-1])
        for a, rho, s_i, y_i in reversed(alphas):
            b = rho * (y_i @ q)
            q += s_i * (a - b)
        d = -q
        slope = g @ d
        if slope >= 0:  # direção ruim (erro numérico): recomeça do gradiente
            s_hist.clear()
            y_hist.clear()
            d, slope = -g, -(g @ g)
        step = 1.0 if s_hist else 1.0 / max(1.0, float(np.linalg.norm(g)))
        for _ in range(40):
            f_new, g_new = fun(x + step * d)
            if f_new <= f + 1e-4 * step * slope:
                break
            step *= 0.5
        else:
            return x, False, it  # sem progresso possível
        s_new, y_new = step * d, g_new - g
        if y_new @ s_new > 1e-12:  # só guarda pares com curvatura positiva
            s_hist.append(s_new)
            y_hist.append(y_new)
            if len(s_hist) > m:
                s_hist.pop(0)
                y_hist.pop(0)
        x, f, g = x + s_new, f_new, g_new
    return x, bool(np.max(np.abs(g)) < tol), max_iter


def fit(
    clients: Sequence[Company],
    universe: Sequence[Company],
    features: Sequence[Feature] = DEFAULT_FEATURES,
    *,
    C: float = DEFAULT_C,
    max_negatives: int = DEFAULT_MAX_NEGATIVES,
    seed: int = 0,
) -> LogisticModel:
    """Ajusta "cliente × base". `universe` é a base inteira (clientes
    incluídos, como no baseline)."""
    features = tuple(features)
    rng = random.Random(seed)
    negatives = list(universe)
    if len(negatives) > max_negatives:
        negatives = rng.sample(negatives, max_negatives)

    index: dict[tuple[str, str], int] = {}
    rowid: list[int] = []
    idx: list[int] = []
    labels: list[float] = []
    for company in [*clients, *negatives]:
        row = len(labels)
        labels.append(1.0 if row < len(clients) else 0.0)
        for key, value, _ in _active(company, features):
            rowid.append(row)
            idx.append(index.setdefault((key, value), len(index)))

    n = len(labels)
    d = len(index)
    scale_by_key = {f.key: f.weight for f in features}
    scale = np.ones(d)
    for (key, _), j in index.items():
        scale[j] = scale_by_key[key]

    y = np.array(labels)
    l2 = 1.0 / (C * n) if n else 0.0  # perda média + (1/(2·C·n))·Σw²
    args = (np.array(rowid, dtype=np.int64), np.array(idx, dtype=np.int64),
            scale, y, n, l2)
    theta, converged, n_iter = _lbfgs(
        lambda t: _objective(t, *args), np.zeros(d + 1)
    )

    weights = {k: float(theta[1 + j] * scale[j]) for k, j in index.items()}

    clients_counts = {f.key: Counter() for f in features}
    base_counts = {f.key: Counter() for f in features}
    for company in clients:
        for key, value, _ in _active(company, features):
            clients_counts[key][value] += 1
    for company in universe:
        for key, value, _ in _active(company, features):
            base_counts[key][value] += 1

    return LogisticModel(
        features=features,
        bias=float(theta[0]),
        weights=weights,
        n_clients=len(clients),
        clients_counts=clients_counts,
        base_counts=base_counts,
        n_clients_by_feature={k: sum(c.values()) for k, c in clients_counts.items()},
        n_base_by_feature={k: sum(c.values()) for k, c in base_counts.items()},
        converged=converged,
        n_iter=n_iter,
    )
