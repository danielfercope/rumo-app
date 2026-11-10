import pytest

from app.services.model_comparison import format_table, learning_curve

from .test_priority_score import population


def test_curva_tem_um_ponto_por_modelo_e_tamanho():
    clients, others = population(n_clients=40, n_other=300)
    pts = learning_curve(clients, others, sizes=[10, 20], repeats=2, folds=5)

    assert {(p.model, p.n_clients) for p in pts} == {
        ("baseline", 10), ("baseline", 20), ("logistica", 10), ("logistica", 20),
    }
    assert all(0.0 <= p.auc_mean <= 1.0 and p.auc_std >= 0 for p in pts)
    # há sinal de verdade: os dois modelos ficam bem acima do sorteio
    assert all(p.auc_mean > 0.8 and p.lift10_mean > 2 for p in pts)


def test_mesma_semente_mesmos_numeros():
    clients, others = population(n_clients=30, n_other=200)
    a = learning_curve(clients, others, sizes=[15], repeats=2, seed=5)
    b = learning_curve(clients, others, sizes=[15], repeats=2, seed=5)
    assert a == b


def test_pede_mais_clientes_do_que_existem():
    clients, others = population(n_clients=12, n_other=100)
    with pytest.raises(ValueError):
        learning_curve(clients, others, sizes=[50])


def test_tabela_em_markdown():
    clients, others = population(n_clients=30, n_other=200)
    pts = learning_curve(clients, others, sizes=[10, 20], repeats=2)
    table = format_table(pts)
    lines = table.splitlines()
    assert lines[0].startswith("| clientes | baseline AUC")
    assert len(lines) == 4  # cabeçalho, separador, 2 tamanhos
    assert lines[2].startswith("| 10 |") and lines[3].startswith("| 20 |")
