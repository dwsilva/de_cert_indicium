"""Ingestao diaria do ERP do BanVic.

Fluxo (ELT, sem transformacao na ingestao):

1. ``aguardar_fontes``  - um FileSensor por tabela confere se o arquivo do dia
   ja esta disponivel no compartilhamento do sistema legado.
2. ``preparar_dw``      - cria schemas e a tabela de auditoria (idempotente).
3. ``carga_datalake``   - copia bruta de cada arquivo para o MinIO, particionada
   por data de referencia.
4. ``carga_dw``         - Meltano (tap-csv -> target-postgres) roda em um pod
   dedicado e carrega o schema ``raw`` do Data Warehouse.
5. ``validacao_dw``     - confere contagem, chave nula e duplicidade por tabela.
6. ``registrar_execucao`` - consolida o resultado em ``meta.ingestion_log``.

As etapas 3 e 4 sao independentes e rodam em paralelo; a validacao so comeca
depois que o Meltano termina.

Idempotencia: o objeto no Data Lake e sobrescrito na particao da data e o
target-postgres faz MERGE pelas chaves primarias declaradas no ``meltano.yml``.
Reprocessar a mesma data quantas vezes for preciso produz sempre o mesmo estado.
"""

from __future__ import annotations

import os
from datetime import timedelta

import pendulum
from airflow import DAG
from airflow.operators.empty import EmptyOperator
from airflow.operators.python import PythonOperator
from airflow.providers.cncf.kubernetes.operators.pod import KubernetesPodOperator
from airflow.providers.common.sql.operators.sql import SQLExecuteQueryOperator
from airflow.sensors.filesystem import FileSensor
from airflow.utils.task_group import TaskGroup
from kubernetes.client import models as k8s

from banvic.config import TABELAS, settings
from banvic.datalake import enviar_para_datalake
from banvic.monitoring import consolidar_execucao, registrar_falha
from banvic.quality import validar_tabela

CFG = settings()

# Politica padrao das tasks: erros transitorios (pod que nao sobe, banco que
# ainda esta subindo) sao reprocessados com backoff; erros de dado usam
# AirflowFailException e interrompem na hora.
DEFAULT_ARGS = {
    "owner": "engenharia-de-dados",
    "depends_on_past": False,
    "retries": 3,
    "retry_delay": timedelta(minutes=1),
    "retry_exponential_backoff": True,
    "max_retry_delay": timedelta(minutes=10),
    "execution_timeout": timedelta(minutes=30),
    "on_failure_callback": registrar_falha,
}

VOLUME_LANDING = k8s.V1Volume(
    name="banvic-landing",
    persistent_volume_claim=k8s.V1PersistentVolumeClaimVolumeSource(
        claim_name=CFG.landing_pvc,
        read_only=True,
    ),
)

MOUNT_LANDING = k8s.V1VolumeMount(
    name="banvic-landing",
    mount_path=CFG.landing_path,
    read_only=True,
)

with DAG(
    dag_id="banvic_erp_ingestao",
    description="Ingestao das 7 tabelas do ERP do BanVic para o Data Lake e o DW",
    doc_md=__doc__,
    schedule="35 4 * * *",
    start_date=pendulum.datetime(2024, 1, 1, tz="America/Sao_Paulo"),
    catchup=False,
    max_active_runs=1,
    dagrun_timeout=timedelta(hours=1),
    default_args=DEFAULT_ARGS,
    template_searchpath=[os.path.join(os.environ.get("AIRFLOW_HOME", "/opt/airflow"), "sql")],
    tags=["banvic", "ingestao", "elt", "erp"],
) as dag:

    inicio = EmptyOperator(task_id="inicio")
    fim = EmptyOperator(task_id="fim")

    # -- 1. disponibilidade dos arquivos de origem --------------------------
    with TaskGroup(
        group_id="aguardar_fontes",
        tooltip="Confere se os arquivos do sistema legado ja chegaram",
    ) as aguardar_fontes:
        for tabela in TABELAS:
            FileSensor(
                task_id=f"aguardar_{tabela.nome}",
                fs_conn_id="fs_banvic",
                filepath=tabela.arquivo,
                poke_interval=15,
                timeout=60 * 10,
                mode="poke",
                soft_fail=False,
            )

    # -- 2. preparacao do destino ------------------------------------------
    preparar_dw = SQLExecuteQueryOperator(
        task_id="preparar_dw",
        conn_id=CFG.conn_dw,
        sql="meta_ingestion_log.sql",
        autocommit=True,
    )

    # -- 3. camada raw do Data Lake ----------------------------------------
    with TaskGroup(
        group_id="carga_datalake",
        tooltip="Copia bruta dos arquivos para o MinIO, particionada por data",
    ) as carga_datalake:
        for tabela in TABELAS:
            PythonOperator(
                task_id=f"datalake_{tabela.nome}",
                python_callable=enviar_para_datalake,
                op_kwargs={
                    "tabela": tabela.nome,
                    "data_referencia": "{{ ds }}",
                },
            )

    # -- 4. carga no Data Warehouse via Meltano ----------------------------
    carga_dw = KubernetesPodOperator(
        task_id="carga_dw",
        name="banvic-meltano-elt",
        namespace=CFG.namespace,
        image=CFG.meltano_image,
        image_pull_policy="IfNotPresent",
        cmds=["meltano"],
        arguments=["run", "tap-csv", "target-postgres"],
        env_from=[
            k8s.V1EnvFromSource(
                secret_ref=k8s.V1SecretEnvSource(name=CFG.pipeline_secret)
            )
        ],
        volumes=[VOLUME_LANDING],
        volume_mounts=[MOUNT_LANDING],
        container_resources=k8s.V1ResourceRequirements(
            requests={"cpu": "250m", "memory": "512Mi"},
            limits={"memory": "2Gi"},
        ),
        labels={"app": "banvic-meltano", "pipeline": "erp-ingestao"},
        in_cluster=True,
        get_logs=True,
        log_events_on_failure=True,
        startup_timeout_seconds=300,
        # Pods com falha ficam de pe para diagnostico; os bem sucedidos somem.
        on_finish_action="delete_succeeded_pod",
        reattach_on_restart=True,
        execution_timeout=timedelta(minutes=45),
    )

    # -- 5. qualidade -------------------------------------------------------
    with TaskGroup(
        group_id="validacao_dw",
        tooltip="Compara origem e destino tabela a tabela",
    ) as validacao_dw:
        for tabela in TABELAS:
            PythonOperator(
                task_id=f"validar_{tabela.nome}",
                python_callable=validar_tabela,
                op_kwargs={"tabela": tabela.nome},
                retries=1,
            )

    # -- 6. auditoria -------------------------------------------------------
    registrar_execucao = PythonOperator(
        task_id="registrar_execucao",
        python_callable=consolidar_execucao,
    )

    inicio >> aguardar_fontes >> preparar_dw >> [carga_datalake, carga_dw]
    carga_dw >> validacao_dw
    [carga_datalake, validacao_dw] >> registrar_execucao >> fim
