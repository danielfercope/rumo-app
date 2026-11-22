"""Sinais tributários de uma empresa, a partir dos dados públicos já buscados.

Funções puras: recebem o `dados` das fontes `receita` e `compras` do
enriquecimento (formato de `enrichment/receita.py` e `enrichment/compras.py`)
e devolvem um `Signals` com o que as regras precisam. Nada aqui chama rede.

A janela é a da prescrição do indébito tributário (CTN art. 168): 5 anos.
O ano corrente conta, então em 2026 a janela é 2022–2026."""

from dataclasses import dataclass, field
from datetime import date

JANELA_ANOS = 5

PRESUMIDO = "presumido"
REAL = "real"
ARBITRADO = "arbitrado"
IMUNE = "imune"
ISENTA = "isenta"
SIMPLES = "simples"


@dataclass(frozen=True)
class Signals:
    hoje: date
    situacao: str | None
    situacao_ativa: bool
    mei: bool
    # ano → regime (simples, presumido, real, arbitrado, imune, isenta), só na janela
    regimes: dict[int, str] = field(default_factory=dict)
    simples_desde: date | None = None
    simples_excluido_em: date | None = None
    cnae_principal: str | None = None  # 7 dígitos
    cnae_principal_descricao: str | None = None
    cnaes_secundarios: tuple[str, ...] = ()
    porte: str | None = None
    abertura: date | None = None
    compras_recente: float | None = None  # None = fonte sem dado
    compras_anterior: float | None = None
    compras_orgaos: int = 0

    @property
    def inicio_janela(self) -> int:
        return self.hoje.year - JANELA_ANOS + 1

    def anos(self, *regimes: str) -> list[int]:
        """Anos da janela em algum dos regimes pedidos, em ordem."""
        return sorted(a for a, r in self.regimes.items() if r in regimes)

    @property
    def cnaes(self) -> tuple[str, ...]:
        return ((self.cnae_principal,) if self.cnae_principal else ()) + self.cnaes_secundarios

    @property
    def mudancas_de_regime(self) -> list[tuple[int, str, str]]:
        """(ano, de, para) para cada troca de regime dentro da janela."""
        anos = sorted(self.regimes)
        return [
            (b, self.regimes[a], self.regimes[b])
            for a, b in zip(anos, anos[1:])
            if b == a + 1 and self.regimes[a] != self.regimes[b]
        ]

    @property
    def compras_total(self) -> float:
        return (self.compras_recente or 0.0) + (self.compras_anterior or 0.0)


def _parse_date(value) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(str(value)[:10])
    except ValueError:
        return None


def _digits(value) -> str:
    return "".join(ch for ch in str(value or "") if ch.isdigit())


def _cnae(c) -> str | None:
    d = _digits((c or {}).get("codigo"))
    return d.zfill(7) if d and int(d) else None


def regime_key(forma: str | None) -> str | None:
    """Nome do regime como vem dos dados abertos da Receita → chave interna."""
    f = (forma or "").upper()
    if "PRESUMIDO" in f:
        return PRESUMIDO
    if "REAL" in f:
        return REAL
    if "ARBITRADO" in f:
        return ARBITRADO
    if "IMUNE" in f:
        return IMUNE
    if "ISENT" in f:
        return ISENTA
    return None


def extract(receita: dict, compras: dict | None, hoje: date) -> Signals:
    """`receita` e `compras` são o `dados` das fontes do enriquecimento."""
    inicio = hoje.year - JANELA_ANOS + 1

    simples = receita.get("simples") or {}
    simples_desde = _parse_date(simples.get("desde"))
    simples_excluido = _parse_date(simples.get("excluido_em"))

    regimes: dict[int, str] = {}
    # Simples: dos dados de opção/exclusão (o histórico de regimes da Receita
    # só traz quem declara IRPJ fora do Simples).
    if simples_desde and (simples.get("optante") or simples_excluido):
        fim = simples_excluido.year - 1 if simples_excluido else hoje.year
        # excluído em 1º de janeiro: o ano da exclusão já é fora do Simples
        if simples_excluido and (simples_excluido.month, simples_excluido.day) != (1, 1):
            fim = simples_excluido.year
        for ano in range(max(simples_desde.year, inicio), fim + 1):
            regimes[ano] = SIMPLES
    elif simples.get("optante"):
        regimes[hoje.year] = SIMPLES
    # Histórico declarado (Presumido/Real/...) vence o que foi inferido acima
    for r in receita.get("regime_tributario") or []:
        ano, key = r.get("ano"), regime_key(r.get("forma"))
        if key and isinstance(ano, int) and inicio <= ano <= hoje.year:
            regimes[ano] = key

    situacao = ((receita.get("situacao") or {}).get("descricao") or "").strip() or None
    principal = receita.get("cnae_principal") or {}

    recente = anterior = None
    orgaos = 0
    if compras is not None:
        rec = compras.get("ultimos_12_meses") or {}
        ant = compras.get("12_meses_anteriores") or {}
        recente = float(rec.get("valor") or 0)
        anterior = float(ant.get("valor") or 0)
        orgaos = int(rec.get("orgaos") or 0)

    return Signals(
        hoje=hoje,
        situacao=situacao,
        situacao_ativa=(situacao or "").upper() == "ATIVA",
        mei=bool((receita.get("mei") or {}).get("optante")),
        regimes=regimes,
        simples_desde=simples_desde,
        simples_excluido_em=simples_excluido,
        cnae_principal=_cnae(principal),
        cnae_principal_descricao=principal.get("descricao"),
        cnaes_secundarios=tuple(
            c for c in (_cnae(x) for x in receita.get("cnaes_secundarios") or []) if c
        ),
        porte=receita.get("porte"),
        abertura=_parse_date(receita.get("abertura")),
        compras_recente=recente,
        compras_anterior=anterior,
        compras_orgaos=orgaos,
    )
