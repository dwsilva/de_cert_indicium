"""Testes estruturais das DAGs.

Rodam sem cluster e sem banco: servem de rede de protecao contra erro de import,
ciclo de dependencia e regressao nas politicas de resiliencia (retries, timeout,
callback de falha). Execucao: ``make test``.
"""

from __future__ import annotations

import pytest
from airflow.models import DagBag

DAG_ID = "banvic_erp_ingestao"

TABELAS = (
    "agencias",
    "clientes",
    "colaboradores",
    "colaborador_agencia",
    "contas",
    "propostas_credito",
    "transacoes",
)


@pytest.fixture(scope="session")
def dagbag() -> DagBag:
    return DagBag(dag_folder="/opt/airflow/dags", include_examples=False)


def test_dags_importam_sem_erro(dagbag: DagBag) -> None:
    assert not dagbag.import_errors, f"Erros de import: {dagbag.import_errors}"


def test_dag_registrada(dagbag: DagBag) -> None:
    assert DAG_ID in dagbag.dags


def test_agendamento_e_concorrencia(dagbag: DagBag) -> None:
    dag = dagbag.dags[DAG_ID]
    assert dag.catchup is False
    # Duas execucoes simultaneas escreveriam na mesma particao do Data Lake.
    assert dag.max_active_runs == 1
    assert dag.tags


@pytest.mark.parametrize("tabela", TABELAS)
def test_toda_tabela_tem_sensor_lake_e_validacao(dagbag: DagBag, tabela: str) -> None:
    ids = set(dagbag.dags[DAG_ID].task_ids)
    assert f"aguardar_fontes.aguardar_{tabela}" in ids
    assert f"carga_datalake.datalake_{tabela}" in ids
    assert f"validacao_dw.validar_{tabela}" in ids


def test_politica_de_resiliencia(dagbag: DagBag) -> None:
    dag = dagbag.dags[DAG_ID]
    for task in dag.tasks:
        assert task.retries >= 1, f"{task.task_id} sem retries"
        assert task.on_failure_callback, f"{task.task_id} sem callback de falha"
        assert task.execution_timeout is not None, f"{task.task_id} sem timeout"


def test_dependencias_principais(dagbag: DagBag) -> None:
    dag = dagbag.dags[DAG_ID]

    preparar = dag.get_task("preparar_dw")
    assert "carga_dw" in preparar.downstream_task_ids

    carga_dw = dag.get_task("carga_dw")
    assert any(t.startswith("validacao_dw.") for t in carga_dw.downstream_task_ids)

    registrar = dag.get_task("registrar_execucao")
    upstream = registrar.upstream_task_ids
    assert any(t.startswith("carga_datalake.") for t in upstream)
    assert any(t.startswith("validacao_dw.") for t in upstream)


def test_sem_ciclos(dagbag: DagBag) -> None:
    # test_cycle levanta AirflowDagCycleException se houver ciclo.
    from airflow.utils.dag_cycle_tester import check_cycle

    check_cycle(dagbag.dags[DAG_ID])
