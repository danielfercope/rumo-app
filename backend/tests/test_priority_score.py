import random
from datetime import date

import pytest

from app.services.priority_score import (
    MIN_CLIENTS,
    _auc,
    evaluate,
    fit,
    percentile_scores,
)

UFS = ["SC", "PR", "RS", "SP"]


def company(i, *, cnae="4771701", uf="SC", porte="me", segmento="farmácia", **extra):
    return {
        "cnpj": f"{i:014d}",
        "cnae_principal": cnae,
        "uf": uf,
        "municipio": "Joinville",
        "porte": porte,
        "segmento": segmento,
        "natureza_juridica": "ltda",
        "data_abertura": "2015-03-01",
        **extra,
    }


def population(n_clients=40, n_other=400, seed=1):
    """Clientes concentrados em farmácias de SC; o resto é variado."""
    rng = random.Random(seed)
    clients = [company(i, porte=rng.choice(["me", "me", "epp"])) for i in range(n_clients)]
    others = [
        company(
            1000 + i,
            cnae=rng.choice(["4771701", "4711302", "5611201", "4930201", "6201501"]),
            uf=rng.choice(UFS),
            porte=rng.choice(["me", "epp", "demais"]),
            segmento=rng.choice(["farmácia", "mercado", "restaurante", "transporte"]),
        )
        for i in range(n_other)
    ]
    return clients, others


def test_empresa_parecida_com_clientes_pontua_mais_que_a_diferente():
    clients, others = population()
    model = fit(clients, clients + others)
    parecida = model.score(company(1))
    diferente = model.score(
        company(2, cnae="4930201", uf="RS", porte="demais", segmento="transporte")
    )
    assert parecida.raw > 0 > diferente.raw


def test_explica_com_os_motivos_que_mais_pesam():
    clients, others = population()
    scored = fit(clients, clients + others).score(company(1))
    top = scored.top_reasons(3)
    assert top and all(r.contribution > 0 for r in top)
    assert top == sorted(top, key=lambda r: r.contribution, reverse=True)
    segmento = next(r for r in scored.reasons if r.feature == "segmento")
    assert segmento.value == "farmácia"
    assert segmento.share_clients == 1.0 and segmento.share_base < 0.5


def test_dado_ausente_nao_pune_nem_premia():
    clients, others = population()
    model = fit(clients, clients + others)
    vazia = model.score({"cnpj": "1"})
    assert vazia.raw == 0.0 and vazia.reasons == ()
    # só com o segmento, vale a média ponderada (não a soma): nota do mesmo
    # patamar de uma empresa completa, não ~0
    so_segmento = model.score({"segmento": "farmácia"})
    assert so_segmento.raw > 0


def test_valor_nunca_visto_nao_quebra():
    clients, others = population()
    scored = fit(clients, clients + others).score(company(1, uf="AC"))
    assert any(r.feature == "uf" and r.value == "ac" for r in scored.reasons)


def test_pouca_evidencia_pesa_menos_que_muita_na_mesma_frequencia_da_base():
    # o valor tem a mesma frequência na base (10%) nos dois casos; só muda
    # quantos clientes o têm: 1 de 1 não pode valer tanto quanto 20 de 20.
    outros = [company(i, cnae="4711302") for i in range(180)]
    alvo = [company(500 + i, cnae="4771701") for i in range(20)]
    base = outros + alvo
    um = fit(alvo[:1], base)
    vinte = fit(alvo, base)

    def peso(model):
        scored = model.score(company(1))
        return next(r for r in scored.reasons if r.feature == "cnae_classe").contribution

    assert 0 < peso(um) < 0.6 * peso(vinte)


def test_confiavel_so_com_clientes_suficientes():
    clients, others = population(n_clients=MIN_CLIENTS - 1)
    assert not fit(clients, clients + others).reliable
    clients, others = population(n_clients=MIN_CLIENTS)
    assert fit(clients, clients + others).reliable


def test_idade_em_faixas():
    clients, others = population()
    model = fit(clients, clients + others)
    novo = model.score(company(1, data_abertura=date(date.today().year, 1, 1)))
    assert any(r.feature == "idade" and r.value == "<2 anos" for r in novo.reasons)
    assert not any(
        r.feature == "idade" for r in model.score(company(1, data_abertura="lixo")).reasons
    )


def test_percentil_ordena_e_empates_recebem_a_mesma_nota():
    assert percentile_scores([]) == []
    assert percentile_scores([3.0]) == [50]
    assert percentile_scores([1.0, 3.0, 2.0]) == [0, 100, 50]
    assert percentile_scores([1.0, 1.0, 2.0]) == [25, 25, 100]


def test_auc_casos_conhecidos():
    assert _auc([3, 4], [1, 2]) == 1.0
    assert _auc([1, 2], [3, 4]) == 0.0
    assert _auc([1], [1]) == 0.5


def test_avaliacao_com_sinal_real_supera_o_sorteio():
    clients, others = population()
    ev = evaluate(clients, others, folds=5, seed=3)
    assert ev.auc > 0.9
    assert ev.recall_at[0.1] > 3 * ev.random_recall_at[0.1]
    assert ev.lift_at(0.1) > 3


def test_avaliacao_sem_sinal_fica_perto_do_sorteio():
    # clientes escolhidos ao acaso: o score não pode "inventar" desempenho
    rng = random.Random(7)
    everyone = [
        company(
            i,
            cnae=rng.choice(["4771701", "4711302", "5611201", "4930201", "6201501"]),
            uf=rng.choice(UFS),
            porte=rng.choice(["me", "epp", "demais"]),
            segmento=rng.choice(["farmácia", "mercado", "restaurante", "transporte"]),
        )
        for i in range(1500)
    ]
    ev = evaluate(everyone[:60], everyone[60:], folds=5, seed=1)
    assert 0.4 < ev.auc < 0.6


def test_avaliacao_exige_clientes_para_as_dobras():
    clients, others = population(n_clients=3)
    with pytest.raises(ValueError):
        evaluate(clients, others, folds=5)
