"""Catalogo de entidades do ERP e configuracao do ambiente.

Tudo que muda entre ambientes chega por variavel de ambiente. Credenciais nunca
aparecem aqui: elas vivem em Secrets do Kubernetes e sao consumidas pelo Airflow
como Connections (``banvic_dw``, ``minio_s3``) ou injetadas diretamente nos pods
do Meltano.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class Tabela:
    """Uma tabela do ERP de origem.

    ``chaves`` e a chave primaria usada pelo Meltano para fazer MERGE no destino
    (e o que garante que reprocessar a mesma data nao duplique registros).
    """

    nome: str
    chaves: tuple[str, ...]
    descricao: str

    @property
    def arquivo(self) -> str:
        return f"{self.nome}.csv"


TABELAS: tuple[Tabela, ...] = (
    Tabela("agencias", ("cod_agencia",), "Agencias fisicas e digitais do banco"),
    Tabela("clientes", ("cod_cliente",), "Cadastro de clientes PF e PJ"),
    Tabela("colaboradores", ("cod_colaborador",), "Cadastro de colaboradores"),
    Tabela(
        "colaborador_agencia",
        ("cod_colaborador", "cod_agencia"),
        "Relacao N:N entre colaboradores e agencias",
    ),
    Tabela("contas", ("num_conta",), "Contas correntes e respectivos saldos"),
    Tabela(
        "propostas_credito",
        ("cod_proposta",),
        "Propostas de credito (foco do piloto de analytics)",
    ),
    Tabela("transacoes", ("cod_transacao",), "Movimentacoes financeiras das contas"),
)

TABELAS_POR_NOME = {t.nome: t for t in TABELAS}


@dataclass(frozen=True)
class Settings:
    landing_path: str
    bucket: str
    schema_raw: str
    sistema_origem: str
    namespace: str
    meltano_image: str
    landing_pvc: str
    pipeline_secret: str
    conn_dw: str
    conn_object_storage: str


@lru_cache(maxsize=1)
def settings() -> Settings:
    """Le a configuracao do ambiente uma unica vez por processo."""
    return Settings(
        landing_path=os.getenv("BANVIC_LANDING_PATH", "/opt/banvic/landing"),
        bucket=os.getenv("BANVIC_MINIO_BUCKET", "banvic-datalake"),
        schema_raw=os.getenv("BANVIC_DW_SCHEMA", "raw"),
        sistema_origem=os.getenv("BANVIC_SOURCE_SYSTEM", "erp"),
        namespace=os.getenv("BANVIC_NAMESPACE", "banvic"),
        meltano_image=os.getenv("BANVIC_MELTANO_IMAGE", "banvic/meltano:local"),
        landing_pvc=os.getenv("BANVIC_LANDING_PVC", "banvic-landing"),
        pipeline_secret=os.getenv("BANVIC_PIPELINE_SECRET", "banvic-pipeline-env"),
        conn_dw="banvic_dw",
        conn_object_storage="minio_s3",
    )


def caminho_origem(tabela: Tabela) -> str:
    """Caminho do arquivo do sistema legado dentro do pod."""
    return os.path.join(settings().landing_path, tabela.arquivo)


def chave_datalake(tabela: Tabela, data_referencia: str) -> str:
    """Chave do objeto no Data Lake.

    O particionamento por data de referencia e o que torna a carga idempotente:
    reexecutar a mesma data sobrescreve exatamente o mesmo objeto.
    """
    cfg = settings()
    return (
        f"raw/{cfg.sistema_origem}/{tabela.nome}"
        f"/data_referencia={data_referencia}/{tabela.arquivo}"
    )
