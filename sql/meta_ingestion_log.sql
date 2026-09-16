-- Estrutura de controle do pipeline.
-- Executada no inicio de toda DAG run: e idempotente e garante que o ambiente
-- esteja pronto mesmo em um cluster recem-criado.

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS meta;

CREATE TABLE IF NOT EXISTS meta.ingestion_log (
    id              BIGINT      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dag_id          TEXT        NOT NULL,
    run_id          TEXT        NOT NULL,
    data_referencia DATE        NOT NULL,
    camada          TEXT        NOT NULL,
    entidade        TEXT        NOT NULL,
    status          TEXT        NOT NULL,
    registros       BIGINT,
    detalhe         TEXT,
    registrado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT ingestion_log_uk UNIQUE (run_id, camada, entidade)
);

COMMENT ON TABLE meta.ingestion_log IS
    'Auditoria das execucoes de ingestao: uma linha por camada/entidade/run';

-- Ultimo status conhecido de cada entidade, para consulta rapida.
CREATE OR REPLACE VIEW meta.vw_ultima_ingestao AS
SELECT DISTINCT ON (camada, entidade)
       camada,
       entidade,
       status,
       registros,
       data_referencia,
       registrado_em,
       run_id
  FROM meta.ingestion_log
 ORDER BY camada, entidade, registrado_em DESC;
