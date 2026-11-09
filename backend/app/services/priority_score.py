"""Score de prioridade (baseline transparente): quão parecida com os clientes
de uma organização é cada empresa candidata.

Não usa aprendizado de máquina de propósito. É um "lookalike" por razão de
chances (naive Bayes com a priori na base): pra cada característica da empresa
(segmento, CNAE, porte, UF...), compara a frequência do valor entre os
CLIENTES da organização com a frequência na base inteira de empresas. Valor
mais comum entre clientes do que na base empurra o score pra cima; menos
comum, pra baixo. Cada parcela é guardada, então toda nota vem com os motivos.

Aprendizado de positivo-não-rotulado: só se conhecem os clientes; o resto
(leads, perdidos, empresas nunca contatadas) é "não rotulado", não "negativo".
Por isso a base de comparação é o universo inteiro, e não os não-clientes.

Funções puras sobre dicts — sem banco nem rede — pra serem fáceis de testar e
de avaliar offline (`evaluate`). Este baseline é o piso que um modelo mais
complexo (regressão logística, GBM) precisa superar."""

import math
import random
import re
from collections import Counter
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import date

# Abaixo disso a frequência por valor é ruído; o score sai marcado como
# não confiável (o app deve avisar em vez de fingir precisão).
MIN_CLIENTS = 10

# Força do "a priori": equivale a N clientes fictícios que se distribuem como a
# base inteira. Com poucos clientes reais num valor, a frequência dele entre
# os clientes é puxada pra frequência da base (razão ~1, sem sinal); quanto
# mais clientes reais, mais o dado pesa. Evita que 1 cliente num CNAE raro
# valha mais que 20 num CNAE comum.
DEFAULT_ALPHA = 5.0

Company = Mapping[str, object]
Extractor = Callable[[Company], str | None]


def _digits(value: object) -> str:
    return re.sub(r"\D", "", str(value or ""))


def _text(key: str) -> Extractor:
    def extract(company: Company) -> str | None:
        value = str(company.get(key) or "").strip().lower()
        return value or None

    return extract


_CODE_ONLY = re.compile(r"^[\d.\-/\s]+$")


def _cnae_code(company: Company) -> str | None:
    """Dígitos do CNAE quando o campo traz o CÓDIGO (47.71-7/01); None quando
    traz a descrição. A BrasilAPI preenche `companies.cnae_principal` com a
    descrição, então com dados reais o código quase nunca está disponível."""
    raw = str(company.get("cnae_principal") or "").strip()
    return _digits(raw) if raw and _CODE_ONLY.match(raw) else None


def _cnae_divisao(company: Company) -> str | None:
    code = _cnae_code(company)
    return code[:2] if code and len(code) >= 2 else None


def _cnae_classe(company: Company) -> str | None:
    """Atividade no nível da subclasse: o código (5 dígitos) se houver, senão a
    própria descrição, que identifica a atividade do mesmo jeito."""
    code = _cnae_code(company)
    if code:
        return code[:5] if len(code) >= 5 else None
    text = str(company.get("cnae_principal") or "").strip().lower()
    return text or None


def _municipio(company: Company) -> str | None:
    cidade = str(company.get("municipio") or "").strip().lower()
    uf = str(company.get("uf") or "").strip().lower()
    return f"{uf}/{cidade}" if cidade and uf else None


def _idade(company: Company, today: date | None = None) -> str | None:
    opened = company.get("data_abertura")
    if isinstance(opened, str):
        try:
            opened = date.fromisoformat(opened[:10])
        except ValueError:
            return None
    if not isinstance(opened, date):
        return None
    years = ((today or date.today()) - opened).days / 365.25
    if years < 2:
        return "<2 anos"
    if years < 5:
        return "2-5 anos"
    if years < 10:
        return "5-10 anos"
    if years < 20:
        return "10-20 anos"
    return "20+ anos"


@dataclass(frozen=True)
class Feature:
    key: str
    label: str
    extract: Extractor
    weight: float = 1.0


# O peso de cada característica é o ponto de partida "por julgamento" (AHP
# entra depois, pra derivá-los de comparações pareadas); com a carteira
# suficiente, um modelo ajustado aos dados substitui estes pesos.
DEFAULT_FEATURES: tuple[Feature, ...] = (
    Feature("cnae_divisao", "Atividade (CNAE, divisão)", _cnae_divisao, 1.0),
    Feature("cnae_classe", "Atividade (CNAE, classe)", _cnae_classe, 1.0),
    Feature("segmento", "Segmento", _text("segmento"), 1.0),
    Feature("porte", "Porte", _text("porte"), 0.8),
    Feature("natureza_juridica", "Natureza jurídica", _text("natureza_juridica"), 0.5),
    Feature("uf", "Estado", _text("uf"), 0.5),
    Feature("municipio", "Cidade", _municipio, 0.7),
    Feature("idade", "Tempo de abertura", _idade, 0.6),
    Feature("faixa_faturamento", "Faturamento", _text("faixa_faturamento"), 0.8),
    Feature("regime_tributario", "Regime tributário", _text("regime_tributario"), 0.4),
)


@dataclass(frozen=True)
class Reason:
    feature: str
    label: str
    value: str
    contribution: float  # > 0 empurra pra cima, < 0 pra baixo
    share_clients: float  # % dos clientes com esse valor
    share_base: float  # % da base com esse valor


@dataclass(frozen=True)
class Scored:
    raw: float
    reasons: tuple[Reason, ...]

    def top_reasons(self, n: int = 3) -> list[Reason]:
        """Os n motivos que mais ajudam a empresa (só os positivos)."""
        positive = [r for r in self.reasons if r.contribution > 0]
        return sorted(positive, key=lambda r: r.contribution, reverse=True)[:n]


@dataclass
class _Table:
    clients: Counter = field(default_factory=Counter)
    base: Counter = field(default_factory=Counter)
    n_clients: int = 0
    n_base: int = 0

    @property
    def cardinality(self) -> int:
        # +1: reserva massa pra valores nunca vistos.
        return len(set(self.clients) | set(self.base)) + 1


MODEL_VERSION = 1


@dataclass
class PriorityModel:
    features: tuple[Feature, ...]
    tables: dict[str, _Table]
    n_clients: int
    alpha: float = DEFAULT_ALPHA

    def to_json(self) -> dict:
        """Forma gravável em jsonb. Guarda só as contagens: as funções de
        extração e os pesos vêm do código (por chave da característica)."""
        return {
            "version": MODEL_VERSION,
            "alpha": self.alpha,
            "n_clients": self.n_clients,
            "tables": {
                key: {
                    "n_clients": t.n_clients,
                    "n_base": t.n_base,
                    "clients": dict(t.clients),
                    "base": dict(t.base),
                }
                for key, t in self.tables.items()
            },
        }

    @classmethod
    def from_json(
        cls, data: Mapping, features: Sequence[Feature] = DEFAULT_FEATURES
    ) -> "PriorityModel":
        if data.get("version") != MODEL_VERSION:
            raise ValueError("Versão de modelo desconhecida")
        stored = data["tables"]
        tables = {}
        for feature in features:
            t = stored.get(feature.key) or {}
            tables[feature.key] = _Table(
                clients=Counter(t.get("clients") or {}),
                base=Counter(t.get("base") or {}),
                n_clients=t.get("n_clients", 0),
                n_base=t.get("n_base", 0),
            )
        return cls(tuple(features), tables, data["n_clients"], data["alpha"])

    @property
    def reliable(self) -> bool:
        return self.n_clients >= MIN_CLIENTS

    def score(self, company: Company) -> Scored:
        reasons: list[Reason] = []
        total = 0.0
        used_weight = 0.0
        for feature in self.features:
            value = feature.extract(company)
            table = self.tables[feature.key]
            if value is None or table.n_clients == 0:
                continue  # dado ausente não pune nem premia
            k = table.cardinality
            # base com suavização mínima (valor nunca visto não vira 0)
            p_base = (table.base[value] + 1) / (table.n_base + k)
            p_client = (table.clients[value] + self.alpha * p_base) / (
                table.n_clients + self.alpha
            )
            contribution = feature.weight * math.log(p_client / p_base)
            total += contribution
            used_weight += feature.weight
            reasons.append(
                Reason(
                    feature=feature.key,
                    label=feature.label,
                    value=value,
                    contribution=contribution,
                    share_clients=table.clients[value] / table.n_clients,
                    share_base=table.base[value] / table.n_base
                    if table.n_base
                    else 0.0,
                )
            )
        # Média ponderada (não soma): empresas com mais campos preenchidos não
        # ganham nota maior só por terem mais dados.
        raw = total / used_weight if used_weight else 0.0
        return Scored(raw=raw, reasons=tuple(reasons))


def fit(
    clients: Sequence[Company],
    universe: Sequence[Company],
    features: Sequence[Feature] = DEFAULT_FEATURES,
    alpha: float = DEFAULT_ALPHA,
) -> PriorityModel:
    """Aprende o perfil dos clientes. `universe` é a base inteira (clientes
    incluídos) contra a qual o perfil é comparado."""
    tables: dict[str, _Table] = {}
    for feature in features:
        table = _Table()
        for company in clients:
            value = feature.extract(company)
            if value is not None:
                table.clients[value] += 1
                table.n_clients += 1
        for company in universe:
            value = feature.extract(company)
            if value is not None:
                table.base[value] += 1
                table.n_base += 1
        tables[feature.key] = table
    return PriorityModel(tuple(features), tables, len(clients), alpha)


def percentile_scores(raws: Sequence[float]) -> list[int]:
    """Converte notas brutas em 0-100 por posição entre os candidatos ("mais
    parecida que 87% dos candidatos"). A razão de chances em si não é legível
    pro usuário; o ranking é."""
    n = len(raws)
    if n == 0:
        return []
    if n == 1:
        return [50]
    order = sorted(range(n), key=lambda i: raws[i])
    out = [0] * n
    i = 0
    while i < n:  # empates recebem a mesma nota
        j = i
        while j + 1 < n and raws[order[j + 1]] == raws[order[i]]:
            j += 1
        pct = round(100 * ((i + j) / 2) / (n - 1))
        for idx in order[i : j + 1]:
            out[idx] = pct
        i = j + 1
    return out


@dataclass(frozen=True)
class Evaluation:
    folds: int
    n_clients: int
    n_candidates: int
    auc: float  # 0,5 = sorteio; 1 = perfeito
    recall_at: dict[float, float]  # fração do topo → fração dos clientes retidos
    random_recall_at: dict[float, float]  # o que um sorteio acertaria

    def lift_at(self, fraction: float) -> float:
        return self.recall_at[fraction] / self.random_recall_at[fraction]


def _auc(positives: Sequence[float], negatives: Sequence[float]) -> float:
    """P(nota de um positivo > nota de um negativo), empates valendo 1/2."""
    if not positives or not negatives:
        return float("nan")
    ordered = sorted(
        [(s, 1) for s in positives] + [(s, 0) for s in negatives],
        key=lambda t: t[0],
    )
    rank_sum = 0.0
    i = 0
    while i < len(ordered):
        j = i
        while j + 1 < len(ordered) and ordered[j + 1][0] == ordered[i][0]:
            j += 1
        avg_rank = (i + j) / 2 + 1
        rank_sum += avg_rank * sum(label for _, label in ordered[i : j + 1])
        i = j + 1
    n_pos, n_neg = len(positives), len(negatives)
    return (rank_sum - n_pos * (n_pos + 1) / 2) / (n_pos * n_neg)


def evaluate(
    clients: Sequence[Company],
    candidates: Sequence[Company],
    folds: int = 5,
    fractions: Sequence[float] = (0.05, 0.1, 0.2),
    seed: int = 0,
    features: Sequence[Feature] = DEFAULT_FEATURES,
    alpha: float = DEFAULT_ALPHA,
    fitter: "Callable[[Sequence[Company], Sequence[Company]], object] | None" = None,
) -> Evaluation:
    """Validação cruzada: esconde uma parte dos clientes, ajusta o modelo com o
    resto e vê onde os escondidos caem no ranking junto com os candidatos.

    A pergunta respondida: "se este cliente ainda fosse um lead, o score o
    teria posto no topo?". O universo de comparação inclui os escondidos
    (como na prática: clientes ainda não conhecidos são "não rotulados")."""
    clients = list(clients)
    candidates = list(candidates)
    if len(clients) < folds:
        raise ValueError("Poucos clientes para a validação cruzada pedida")

    rng = random.Random(seed)
    shuffled = clients[:]
    rng.shuffle(shuffled)
    parts = [shuffled[i::folds] for i in range(folds)]

    universe = clients + candidates
    auc_values: list[float] = []
    kept: dict[float, list[int]] = {f: [] for f in fractions}
    total_held = 0

    for i, held in enumerate(parts):
        train = [c for j, part in enumerate(parts) if j != i for c in part]
        # `fitter` troca o modelo avaliado (ex.: a logística) mantendo a mesma
        # validação, pra os números serem comparáveis entre modelos.
        model = (
            fitter(train, universe)
            if fitter is not None
            else fit(train, universe, features, alpha)
        )
        held_scores = [model.score(c).raw for c in held]
        cand_scores = [model.score(c).raw for c in candidates]
        auc_values.append(_auc(held_scores, cand_scores))

        pool = sorted(
            [(s, 1) for s in held_scores] + [(s, 0) for s in cand_scores],
            key=lambda t: -t[0],
        )
        for fraction in fractions:
            top = max(1, round(len(pool) * fraction))
            kept[fraction].append(sum(label for _, label in pool[:top]))
        total_held += len(held)

    return Evaluation(
        folds=folds,
        n_clients=len(clients),
        n_candidates=len(candidates),
        auc=sum(auc_values) / len(auc_values),
        recall_at={f: sum(kept[f]) / total_held for f in fractions},
        random_recall_at={f: f for f in fractions},
    )
