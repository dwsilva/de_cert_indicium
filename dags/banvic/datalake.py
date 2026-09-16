"""Carga da camada raw do Data Lake (MinIO, protocolo S3).

A estrategia e de copia fiel: o arquivo do sistema legado sobe sem qualquer
transformacao, dentro de uma particao por data de referencia. Isso preserva o
dado original (util para auditoria e para reprocessar o historico) e mantem a
operacao idempotente, ja que reexecutar a mesma data grava sobre o mesmo objeto.
"""

from __future__ import annotations

import csv
import hashlib
import logging
import os
from typing import Any

from airflow.exceptions import AirflowFailException
from airflow.providers.amazon.aws.hooks.s3 import S3Hook

from banvic.config import TABELAS_POR_NOME, caminho_origem, chave_datalake, settings

logger = logging.getLogger(__name__)

# Le o arquivo em blocos para nao carregar 4 MB+ de transacoes na memoria de uma vez.
_CHUNK = 1024 * 1024


def contar_registros_csv(caminho: str) -> int:
    """Conta linhas de dados do CSV (desconta o cabecalho).

    Usa o parser de CSV em vez de contar quebras de linha porque alguns campos
    de endereco do BanVic contem quebras dentro de aspas.
    """
    with open(caminho, newline="", encoding="utf-8") as arquivo:
        leitor = csv.reader(arquivo)
        try:
            next(leitor)
        except StopIteration:
            return 0
        return sum(1 for _ in leitor)


def _checksum(caminho: str) -> str:
    digest = hashlib.sha256()
    with open(caminho, "rb") as arquivo:
        for bloco in iter(lambda: arquivo.read(_CHUNK), b""):
            digest.update(bloco)
    return digest.hexdigest()


def enviar_para_datalake(tabela: str, data_referencia: str) -> dict[str, Any]:
    """Sobe um arquivo da landing zone para o bucket raw do Data Lake."""
    cfg = settings()
    entidade = TABELAS_POR_NOME[tabela]
    origem = caminho_origem(entidade)

    if not os.path.isfile(origem):
        # Arquivo ausente e problema de dado, nao de infraestrutura: nao
        # adianta tentar de novo, entao interrompemos sem consumir retries.
        raise AirflowFailException(f"Arquivo de origem nao encontrado: {origem}")

    registros = contar_registros_csv(origem)
    if registros == 0:
        raise AirflowFailException(f"Arquivo de origem vazio: {origem}")

    chave = chave_datalake(entidade, data_referencia)
    hook = S3Hook(aws_conn_id=cfg.conn_object_storage)
    hook.load_file(
        filename=origem,
        key=chave,
        bucket_name=cfg.bucket,
        replace=True,  # idempotencia: a mesma particao e sempre sobrescrita
    )

    resultado = {
        "entidade": entidade.nome,
        "chave": f"s3://{cfg.bucket}/{chave}",
        "registros": registros,
        "bytes": os.path.getsize(origem),
        "sha256": _checksum(origem),
    }
    logger.info(
        "Data Lake atualizado: %s (%s registros, %s bytes)",
        resultado["chave"],
        resultado["registros"],
        resultado["bytes"],
    )
    return resultado
