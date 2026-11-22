"""Regras do diagnóstico: dos sinais (`signals.py`) às teses do catálogo.

Puro e determinístico. O conteúdo das teses (textos, perguntas, CNAEs) vem do
banco (`catalog.py`); aqui ficam só as condições. Cada regra olha os sinais e
devolve um `Achado` (com pontuação, confiança, evidências e período) ou None.
Tese desativada no banco não aparece. O achado de maior pontuação é a
oportunidade principal; os outros são "outras possibilidades".

Pontuação = base pela confiança + anos dentro da janela + reforços. Tese em
discussão judicial (`em_discussao`) só vira principal quando não há outra."""

from dataclasses import dataclass, field

from .catalog import Catalogo, Tese
from .signals import ARBITRADO, IMUNE, ISENTA, PRESUMIDO, REAL, SIMPLES, Signals

BASE = {"alta": 70, "media": 50, "baixa": 25}
PONTOS_POR_ANO = 3
PONTOS_MUDANCA_REGIME = 8
# vendas ao governo a partir das quais as retenções viram oportunidade média
RETENCOES_VALOR_RELEVANTE = 500_000.0

NOME_REGIME = {
    SIMPLES: "Simples Nacional",
    PRESUMIDO: "Lucro Presumido",
    REAL: "Lucro Real",
    ARBITRADO: "Lucro Arbitrado",
    IMUNE: "Imune do IRPJ",
    ISENTA: "Isenta do IRPJ",
}

F_RECEITA = "Receita Federal"
F_COMPRAS = "Compras públicas (PNCP)"


@dataclass
class Achado:
    tese: Tese
    confianca: str
    anos: list[int]
    evidencias: list[dict] = field(default_factory=list)
    pontos: int = 0

    def to_dict(self) -> dict:
        t = self.tese
        return {
            "id": t.id,
            "titulo": t.titulo,
            "resumo": t.resumo,
            "tributos": list(t.tributos),
            "base_legal": t.base_legal,
            "situacao_juridica": t.situacao_juridica,
            "confianca": self.confianca,
            "periodo": _periodo(self.anos),
            "evidencias": self.evidencias,
            "como_abordar": t.como_abordar,
            "perguntas": list(t.perguntas),
        }


def _periodo(anos: list[int]) -> str | None:
    if not anos:
        return None
    return str(anos[0]) if anos[0] == anos[-1] else f"{anos[0]}–{anos[-1]}"


def _ev(texto: str, fonte: str = F_RECEITA) -> dict:
    return {"texto": texto, "fonte": fonte}


def _brl(v: float) -> str:
    if v >= 1_000_000:
        return f"R$ {v / 1_000_000:.1f} mi".replace(".", ",")
    if v >= 1_000:
        return f"R$ {v / 1_000:.0f} mil"
    return f"R$ {v:.0f}"


def _fmt_cnae(c: str) -> str:
    return f"{c[:2]}.{c[2:4]}-{c[4]}/{c[5:]}"


def _anos_txt(anos: list[int]) -> str:
    n = len(anos)
    return f"{n} ano{'s' if n > 1 else ''} na janela de 5 ({_periodo(anos)})"


# ─── Atividade pelo CNAE (divisão = 2 primeiros dígitos) ────────────────


def divisao(cnae: str | None) -> int | None:
    return int(cnae[:2]) if cnae and cnae[:2].isdigit() else None


def eh_comercio(cnae: str | None) -> bool:
    d = divisao(cnae)
    return d is not None and 45 <= d <= 47


def eh_industria(cnae: str | None) -> bool:
    d = divisao(cnae)
    return d is not None and 5 <= d <= 33


def eh_transporte(cnae: str | None) -> bool:
    d = divisao(cnae)
    return d is not None and 49 <= d <= 53


def eh_agro(cnae: str | None) -> bool:
    d = divisao(cnae)
    return d is not None and 1 <= d <= 3


def eh_servico(cnae: str | None) -> bool:
    """Atividades em geral sujeitas ao ISS (construção e serviços)."""
    d = divisao(cnae)
    return d is not None and (41 <= d <= 43 or (55 <= d <= 99 and d != 84))


# ─── Regras ─────────────────────────────────────────────────────────────


def _monofasico(s: Signals, tese: Tese) -> Achado | None:
    anos = s.anos(SIMPLES)
    if not anos:
        return None
    # CNAE que vende só monofásico vence o de mix amplo (parcial)
    hit = None
    for parcial in (False, True):
        for i, c in enumerate(s.cnaes):
            item = tese.cnaes.get(c)
            if item and item.parcial == parcial:
                hit = (c, item.descricao, i == 0, parcial)
                break
        if hit:
            break
    if hit is None:
        return None
    cnae, produto, principal, parcial = hit
    confianca = "alta" if principal and not parcial else "media"
    onde = "principal" if principal else "secundário"
    return Achado(
        tese,
        confianca,
        anos,
        [
            _ev(f"Optante do Simples Nacional: {_anos_txt(anos)}"),
            _ev(f"CNAE {onde} {_fmt_cnae(cnae)}: revenda de {produto}"),
        ],
    )


def _icms_st(s: Signals, tese: Tese) -> Achado | None:
    anos = s.anos(SIMPLES)
    if not anos:
        return None
    for i, c in enumerate(s.cnaes):
        if c in tese.cnaes and eh_comercio(c):
            onde = "principal" if i == 0 else "secundário"
            return Achado(
                tese,
                "media",
                anos,
                [
                    _ev(f"Optante do Simples Nacional: {_anos_txt(anos)}"),
                    _ev(
                        f"CNAE {onde} {_fmt_cnae(c)}: comércio de "
                        f"{tese.cnaes[c].descricao}, mercadoria em geral com ICMS-ST"
                    ),
                ],
            )
    return None


def _atividade_txt(s: Signals) -> str:
    desc = s.cnae_principal_descricao
    return f"Atividade principal: {desc}" if desc else f"CNAE principal {_fmt_cnae(s.cnae_principal)}"


def _icms_base(s: Signals, tese: Tese) -> Achado | None:
    anos = s.anos(PRESUMIDO, REAL, ARBITRADO)
    c = s.cnae_principal
    if not anos or not (eh_comercio(c) or eh_industria(c)):
        return None
    return Achado(
        tese,
        "media",
        anos,
        [
            _ev(f"{_regimes_txt(s, anos)}: {_anos_txt(anos)}"),
            _ev(f"{_atividade_txt(s)} (venda de mercadorias, com ICMS)"),
        ],
    )


def _insumos(s: Signals, tese: Tese) -> Achado | None:
    anos = s.anos(REAL)
    c = s.cnae_principal
    if not anos or not (eh_industria(c) or eh_transporte(c) or eh_agro(c)):
        return None
    return Achado(
        tese,
        "media",
        anos,
        [
            _ev(f"Lucro Real (não cumulativo): {_anos_txt(anos)}"),
            _ev(f"{_atividade_txt(s)}: operação com muitos insumos"),
        ],
    )


def _retencoes(s: Signals, tese: Tese) -> Achado | None:
    if s.compras_recente is None or s.compras_total <= 0:
        return None
    if s.regimes.get(s.hoje.year) == SIMPLES:
        return None  # optante do Simples não sofre essas retenções
    anos = [a for a in s.anos(PRESUMIDO, REAL, ARBITRADO) if a >= s.hoje.year - 1]
    anos = anos or [s.hoje.year - 1, s.hoje.year]
    confianca = "media" if s.compras_total >= RETENCOES_VALOR_RELEVANTE else "baixa"
    evid = [
        _ev(
            f"Vendeu {_brl(s.compras_total)} a órgãos públicos nos últimos 24 meses"
            + (f" ({s.compras_orgaos} órgão{'s' if s.compras_orgaos != 1 else ''} no último ano)"
               if s.compras_orgaos else ""),
            F_COMPRAS,
        ),
        _ev("Não optante do Simples: sofre retenção na fonte nesses pagamentos"),
    ]
    return Achado(tese, confianca, anos, evid)


def _iss_base(s: Signals, tese: Tese) -> Achado | None:
    anos = s.anos(PRESUMIDO, REAL, ARBITRADO)
    if not anos or not eh_servico(s.cnae_principal):
        return None
    return Achado(
        tese,
        "baixa",
        anos,
        [
            _ev(f"{_regimes_txt(s, anos)}: {_anos_txt(anos)}"),
            _ev(f"{_atividade_txt(s)} (prestação de serviço, com ISS)"),
        ],
    )


def _verbas(s: Signals, tese: Tese) -> Achado | None:
    if s.regimes.get(s.hoje.year) == SIMPLES or (s.porte or "").upper() != "DEMAIS":
        return None
    anos = s.anos(PRESUMIDO, REAL, ARBITRADO) or list(
        range(s.inicio_janela, s.hoje.year + 1)
    )
    return Achado(
        tese,
        "baixa",
        anos,
        [
            _ev("Porte 'Demais' (acima de empresa de pequeno porte): folha tende a ser relevante"),
            _ev("Fora do Simples: recolhe INSS patronal sobre a folha"),
        ],
    )


# id da tese no banco (`teses_tributarias.id`) → condição
REGRAS = {
    "monofasico_simples": _monofasico,
    "icms_st_simples": _icms_st,
    "icms_base_pis_cofins": _icms_base,
    "insumos_lucro_real": _insumos,
    "retencoes_orgaos_publicos": _retencoes,
    "iss_base_pis_cofins": _iss_base,
    "verbas_indenizatorias": _verbas,
}
# Teses de cada regime (pra o reforço de mudança de regime)
TESES_DO_REGIME = {
    SIMPLES: {"monofasico_simples", "icms_st_simples"},
    PRESUMIDO: {"icms_base_pis_cofins", "iss_base_pis_cofins", "retencoes_orgaos_publicos"},
    REAL: {"icms_base_pis_cofins", "insumos_lucro_real", "iss_base_pis_cofins",
           "retencoes_orgaos_publicos"},
}


def _regimes_txt(s: Signals, anos: list[int]) -> str:
    nomes = []
    for a in anos:
        n = NOME_REGIME[s.regimes[a]]
        if n not in nomes:
            nomes.append(n)
    return " e ".join(nomes)


def _reforcar(s: Signals, achado: Achado) -> None:
    achado.pontos = BASE[achado.confianca] + PONTOS_POR_ANO * len(achado.anos)
    for ano, de, para in s.mudancas_de_regime:
        if achado.tese.id in TESES_DO_REGIME.get(para, set()):
            achado.pontos += PONTOS_MUDANCA_REGIME
            achado.evidencias.append(
                _ev(
                    f"Mudou de {NOME_REGIME[de]} para {NOME_REGIME[para]} em {ano}: "
                    "transições de regime costumam gerar erros de apuração"
                )
            )
            break


def diagnose(s: Signals, catalogo: Catalogo) -> dict:
    """Diagnóstico completo (sem o envelope de status, que é do serviço)."""
    if not s.situacao_ativa:
        situacao = (s.situacao or "desconhecida").lower()
        return _result(None, [], {"motivo": f"Situação cadastral {situacao}: não é um lead para recuperação."})
    if s.mei:
        return _result(
            None, [], {"motivo": "MEI recolhe valor fixo mensal: não há tese de recuperação aplicável."}
        )

    achados = [
        a
        for tese_id, regra in REGRAS.items()
        if (tese := catalogo.get(tese_id)) is not None and (a := regra(s, tese)) is not None
    ]
    if s.regimes and s.regimes.get(max(s.regimes)) in (IMUNE, ISENTA):
        achados = [a for a in achados if a.tese.id not in {
            "icms_base_pis_cofins", "insumos_lucro_real", "iss_base_pis_cofins"}]
    for a in achados:
        _reforcar(s, a)

    achados.sort(
        key=lambda a: (not a.tese.em_discussao, a.pontos), reverse=True
    )
    if not achados:
        return _result(None, [], None)
    return _result(achados[0], achados[1:], None)


def _result(principal: Achado | None, outras: list[Achado], bloqueio: dict | None) -> dict:
    return {
        "principal": principal.to_dict() if principal else None,
        "outras": [a.to_dict() for a in outras],
        "bloqueio": bloqueio,
    }
