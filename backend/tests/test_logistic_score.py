import json
import random

import pytest

from app.services import logistic_score as lg
from app.services.priority_score import MIN_CLIENTS, evaluate

from .test_priority_score import company, population


def test_aprende_o_sinal_de_cada_valor():
    clients, others = population()
    model = lg.fit(clients, clients + others)

    farmacia = model.weights[("segmento", "farmácia")]
    transporte = model.weights[("segmento", "transporte")]
    assert farmacia > 0 > transporte


def test_empresa_parecida_pontua_mais_e_explica():
    clients, others = population()
    model = lg.fit(clients, clients + others)

    parecida = model.score(company(1))
    diferente = model.score(
        company(2, cnae="4930201", uf="RS", porte="demais", segmento="transporte")
    )

    assert parecida.raw > diferente.raw
    top = parecida.top_reasons(3)
    assert top and all(r.contribution > 0 for r in top)
    seg = next(r for r in parecida.reasons if r.feature == "segmento")
    assert seg.share_clients == 1.0 and seg.share_base < 0.5


def test_dado_ausente_e_valor_nunca_visto_nao_contam():
    clients, others = population()
    model = lg.fit(clients, clients + others)
    vazia = model.score({"cnpj": "1"})
    assert vazia.reasons == () and vazia.raw == model.bias
    novo = model.score(company(1, uf="AC"))
    assert not any(r.feature == "uf" for r in novo.reasons)


def test_deterministico_com_a_mesma_semente():
    clients, others = population()
    a = lg.fit(clients, clients + others, seed=3)
    b = lg.fit(clients, clients + others, seed=3)
    assert a.weights == b.weights and a.bias == b.bias


def test_pouca_evidencia_pesa_menos_na_mesma_frequencia_da_base():
    outros = [company(i, cnae="4711302", segmento="mercado") for i in range(180)]
    alvo = [company(500 + i, cnae="4771701") for i in range(20)]
    base = outros + alvo

    def peso(clients):
        m = lg.fit(clients, base)
        return m.weights[("cnae_classe", "47717")]

    assert 0 < peso(alvo[:1]) < peso(alvo)


def test_serializa_e_volta_com_as_mesmas_notas():
    clients, others = population()
    model = lg.fit(clients, clients + others)

    restored = lg.LogisticModel.from_json(json.loads(json.dumps(model.to_json())))

    for c in (clients[0], others[0], others[1], {"cnpj": "x"}):
        assert restored.score(c).raw == pytest.approx(model.score(c).raw)
    assert restored.reliable == model.reliable


def test_modelo_de_outro_tipo_ou_versao_e_recusado():
    clients, others = population()
    data = lg.fit(clients, clients + others).to_json()
    with pytest.raises(ValueError):
        lg.LogisticModel.from_json({**data, "version": 99})
    with pytest.raises(ValueError):
        lg.LogisticModel.from_json({**data, "kind": "outro"})


def test_confiavel_so_com_clientes_suficientes():
    clients, others = population(n_clients=MIN_CLIENTS - 1)
    assert not lg.fit(clients, clients + others).reliable


def test_avaliacao_com_sinal_real_supera_o_sorteio():
    clients, others = population()
    ev = evaluate(
        clients, others, folds=5, seed=3, fitter=lambda tr, u: lg.fit(tr, u)
    )
    assert ev.auc > 0.9


def test_avaliacao_sem_sinal_fica_perto_do_sorteio():
    rng = random.Random(7)
    everyone = [
        company(
            i,
            cnae=rng.choice(["4771701", "4711302", "5611201", "4930201", "6201501"]),
            uf=rng.choice(["SC", "PR", "RS", "SP"]),
            porte=rng.choice(["me", "epp", "demais"]),
            segmento=rng.choice(["farmácia", "mercado", "restaurante", "transporte"]),
        )
        for i in range(1500)
    ]
    ev = evaluate(
        everyone[:60], everyone[60:], folds=5, seed=1,
        fitter=lambda tr, u: lg.fit(tr, u),
    )
    assert 0.4 < ev.auc < 0.6


def test_subamostra_da_base_nao_muda_o_sinal():
    clients, others = population(n_other=2000)
    model = lg.fit(clients, clients + others, max_negatives=300)
    assert model.weights[("segmento", "farmácia")] > 0


# ─── Solver ─────────────────────────────────────────────────────────────


def _random_problem(seed=0, n=300, d=12):
    import numpy as np

    rng = np.random.default_rng(seed)
    rowid, idx = [], []
    for r in range(n):
        for j in rng.choice(d, size=3, replace=False):
            rowid.append(r)
            idx.append(int(j))
    truth = rng.normal(size=d)
    z = np.bincount(rowid, weights=truth[idx], minlength=n) - 0.5
    y = (rng.random(n) < 1 / (1 + np.exp(-z))).astype(float)
    return (
        np.array(rowid), np.array(idx), np.ones(d), y, n, 1.0 / (1.0 * n)
    ), d


def _newton_reference(args, d, iters=50):
    """Ótimo exato por Newton com Hessiana densa (só viável em problema pequeno)."""
    import numpy as np

    rowid, idx, scale, y, n, l2 = args
    X = np.zeros((n, d + 1))
    X[:, 0] = 1.0
    for r, j in zip(rowid, idx):
        X[r, 1 + j] = 1.0
    reg = np.diag([0.0] + [l2] * d)
    theta = np.zeros(d + 1)
    for _ in range(iters):
        p = 1 / (1 + np.exp(-X @ theta))
        grad = X.T @ (p - y) / n + reg @ theta
        hess = (X.T * (p * (1 - p))) @ X / n + reg
        theta -= np.linalg.solve(hess, grad)
    return theta


def test_solver_chega_ao_mesmo_otimo_do_newton_exato():
    import numpy as np

    args, d = _random_problem()
    reference = _newton_reference(args, d)

    theta, converged, n_iter = lg._lbfgs(
        lambda t: lg._objective(t, *args), np.zeros(d + 1)
    )

    assert converged and n_iter < lg.MAX_ITERATIONS
    assert np.max(np.abs(theta - reference)) < 1e-4
    _, grad = lg._objective(theta, *args)
    assert np.max(np.abs(grad)) < lg.GRADIENT_TOL


def test_gradiente_analitico_bate_com_o_numerico():
    import numpy as np

    args, d = _random_problem(seed=2)
    theta = np.random.default_rng(5).normal(size=d + 1)
    _, grad = lg._objective(theta, *args)
    eps = 1e-6
    for k in (0, 3, d):
        up, down = theta.copy(), theta.copy()
        up[k] += eps
        down[k] -= eps
        numeric = (lg._objective(up, *args)[0] - lg._objective(down, *args)[0]) / (2 * eps)
        assert grad[k] == pytest.approx(numeric, abs=1e-7)


def test_modelo_ajustado_informa_convergencia():
    clients, others = population()
    model = lg.fit(clients, clients + others)
    assert model.converged and 0 < model.n_iter < lg.MAX_ITERATIONS


def test_ajuste_e_rapido_com_base_grande():
    import time

    clients, others = population(n_clients=200, n_other=8000)
    started = time.perf_counter()
    lg.fit(clients, clients + others)
    assert time.perf_counter() - started < 5
