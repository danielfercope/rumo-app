from datetime import datetime, timezone

from app.services.cold_start_priority import rank_by_interaction, reason


def row(name, interacoes, criado):
    return {"name": name, "num_interacoes": interacoes, "crm_criado_em": criado}


def names(rows):
    return [r["name"] for r in rows]


def test_mais_interacao_vem_primeiro_mesmo_sendo_mais_novo():
    rows = [
        row("velho", 1, "2020-01-01T00:00:00+00:00"),
        row("novo", 9, "2024-01-01T00:00:00+00:00"),
    ]
    assert names(rank_by_interaction(rows)) == ["novo", "velho"]


def test_empate_de_interacao_vai_pro_mais_antigo():
    rows = [
        row("b", 3, "2022-06-01T00:00:00+00:00"),
        row("a", 3, "2021-01-01T00:00:00Z"),
        row("c", 3, "2023-01-01T00:00:00+00:00"),
    ]
    assert names(rank_by_interaction(rows)) == ["a", "b", "c"]


def test_sem_interacao_conta_como_zero_e_sem_data_fica_por_ultimo_no_empate():
    rows = [
        row("sem_data", None, None),
        row("zero_antigo", 0, "2019-01-01T00:00:00+00:00"),
        row("com_uma", 1, None),
    ]
    assert names(rank_by_interaction(rows)) == ["com_uma", "zero_antigo", "sem_data"]


def test_nao_altera_a_lista_de_entrada():
    rows = [row("a", 0, None), row("b", 5, None)]
    rank_by_interaction(rows)
    assert names(rows) == ["a", "b"]


def test_motivo_descreve_interacoes_e_tempo_no_crm():
    hoje = datetime(2024, 1, 31, tzinfo=timezone.utc)
    assert (
        reason(row("a", 3, "2024-01-01T00:00:00+00:00"), hoje)
        == "3 interações · no CRM há 30 dias"
    )
    assert reason(row("a", 1, None), hoje) == "1 interação"
