"""Monitoramento e auditoria das execucoes.

Duas frentes:

1. ``meta.ingestion_log`` no proprio DW guarda o resultado de cada camada por
   execucao. E o primeiro lugar a olhar quando alguem pergunta "o dado de ontem
   entrou?" e serve de base para alertas.
2. ``registrar_falha`` e plugado como ``on_failure_callback`` em todas as tasks:
   qualquer erro vira um registro estruturado no log e uma linha de auditoria
   com status FALHA.
"""

from __future__ import annotations

import logging
from typing import Any

from airflow.providers.postgres.hooks.postgres import PostgresHook

from banvic.config import TABELAS, settings

logger = logging.getLogger(__name__)

_UPSERT = """
    INSERT INTO meta.ingestion_log (
        dag_id, run_id, data_referencia, camada, entidade,
        status, registros, detalhe
    )
    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
    ON CONFLICT (run_id, camada, entidade) DO UPDATE SET
        status        = EXCLUDED.status,
        registros     = EXCLUDED.registros,
        detalhe       = EXCLUDED.detalhe,
        registrado_em = now()
"""


def _registrar(
    *,
    dag_id: str,
    run_id: str,
    data_referencia: str,
    camada: str,
    entidade: str,
    status: str,
    registros: int | None = None,
    detalhe: str | None = None,
) -> None:
    hook = PostgresHook(postgres_conn_id=settings().conn_dw)
    hook.run(
        _UPSERT,
        parameters=(
            dag_id,
            run_id,
            data_referencia,
            camada,
            entidade,
            status,
            registros,
            detalhe,
        ),
    )


def registrar_falha(context: dict[str, Any]) -> None:
    """``on_failure_callback``: registra o erro sem nunca derrubar o callback."""
    ti = context.get("task_instance")
    excecao = context.get("exception")

    logger.error(
        "FALHA | dag=%s task=%s tentativa=%s/%s run=%s erro=%s",
        getattr(ti, "dag_id", "?"),
        getattr(ti, "task_id", "?"),
        getattr(ti, "try_number", "?"),
        getattr(ti, "max_tries", "?"),
        context.get("run_id"),
        excecao,
    )

    try:
        _registrar(
            dag_id=getattr(ti, "dag_id", "desconhecida"),
            run_id=str(context.get("run_id")),
            data_referencia=str(context.get("ds")),
            camada="task",
            entidade=getattr(ti, "task_id", "desconhecida"),
            status="FALHA",
            detalhe=str(excecao)[:2000],
        )
    except Exception:  # noqa: BLE001 - auditoria nunca pode mascarar o erro real
        logger.exception("Nao foi possivel gravar a falha em meta.ingestion_log")


def consolidar_execucao(**context: Any) -> dict[str, Any]:
    """Grava o resumo da execucao a partir dos XComs das tasks anteriores."""
    ti = context["ti"]
    run_id = context["run_id"]
    data_referencia = context["ds"]
    dag_id = ti.dag_id

    total_lake = 0
    total_dw = 0

    for tabela in TABELAS:
        lake = ti.xcom_pull(task_ids=f"carga_datalake.datalake_{tabela.nome}")
        if lake:
            total_lake += lake["registros"]
            _registrar(
                dag_id=dag_id,
                run_id=run_id,
                data_referencia=data_referencia,
                camada="datalake",
                entidade=tabela.nome,
                status="SUCESSO",
                registros=lake["registros"],
                detalhe=lake["chave"],
            )

        dw = ti.xcom_pull(task_ids=f"validacao_dw.validar_{tabela.nome}")
        if dw:
            total_dw += dw["registros"]
            _registrar(
                dag_id=dag_id,
                run_id=run_id,
                data_referencia=data_referencia,
                camada="dw",
                entidade=tabela.nome,
                status="SUCESSO",
                registros=dw["registros"],
            )

    resumo = {
        "run_id": run_id,
        "data_referencia": data_referencia,
        "tabelas": len(TABELAS),
        "registros_datalake": total_lake,
        "registros_dw": total_dw,
    }
    logger.info("Execucao concluida: %s", resumo)
    return resumo
