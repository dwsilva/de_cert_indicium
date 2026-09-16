"""Verificacoes de qualidade da carga no Data Warehouse.

Sao checagens deliberadamente simples e baratas, mas que cobrem as falhas mais
comuns de um pipeline de ingestao: tabela que nao foi criada, carga parcial e
chave primaria nula (que quebraria o MERGE e duplicaria registros).
"""

from __future__ import annotations

import logging
from typing import Any

from airflow.exceptions import AirflowFailException
from airflow.providers.postgres.hooks.postgres import PostgresHook

from banvic.config import TABELAS_POR_NOME, caminho_origem, settings
from banvic.datalake import contar_registros_csv

logger = logging.getLogger(__name__)


def _hook() -> PostgresHook:
    return PostgresHook(postgres_conn_id=settings().conn_dw)


def validar_tabela(tabela: str) -> dict[str, Any]:
    """Compara origem e destino e recusa a carga se houver divergencia."""
    cfg = settings()
    entidade = TABELAS_POR_NOME[tabela]
    destino = f"{cfg.schema_raw}.{entidade.nome}"

    esperado = contar_registros_csv(caminho_origem(entidade))
    hook = _hook()

    existe = hook.get_first(
        "SELECT to_regclass(%s) IS NOT NULL", parameters=(destino,)
    )[0]
    if not existe:
        raise AirflowFailException(f"Tabela {destino} nao foi criada pela carga")

    carregado = hook.get_first(f"SELECT count(*) FROM {destino}")[0]

    condicao_nulos = " OR ".join(f"{coluna} IS NULL" for coluna in entidade.chaves)
    chaves_nulas = hook.get_first(
        f"SELECT count(*) FROM {destino} WHERE {condicao_nulos}"
    )[0]

    colunas_chave = ", ".join(entidade.chaves)
    duplicadas = hook.get_first(
        f"SELECT count(*) FROM ("
        f"  SELECT {colunas_chave} FROM {destino}"
        f"  GROUP BY {colunas_chave} HAVING count(*) > 1"
        f") d"
    )[0]

    problemas = []
    if carregado != esperado:
        problemas.append(
            f"contagem divergente: origem={esperado}, destino={carregado}"
        )
    if chaves_nulas:
        problemas.append(f"{chaves_nulas} registro(s) com chave primaria nula")
    if duplicadas:
        problemas.append(f"{duplicadas} chave(s) primaria(s) duplicada(s)")

    if problemas:
        # Divergencia de dados nao se resolve repetindo a task.
        raise AirflowFailException(f"Falha de qualidade em {destino}: " + "; ".join(problemas))

    logger.info("Qualidade OK em %s: %s registros conferem com a origem", destino, carregado)
    return {"entidade": entidade.nome, "registros": carregado, "esperado": esperado}
