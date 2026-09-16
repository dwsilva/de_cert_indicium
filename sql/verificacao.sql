-- Conferencia rapida do resultado da ingestao.
-- Usado por "make verify" e na demonstracao final.

\echo '== Tabelas carregadas no schema raw =='
SELECT table_name AS tabela
  FROM information_schema.tables
 WHERE table_schema = 'raw'
 ORDER BY table_name;

\echo ''
\echo '== Volume por tabela =='
SELECT 'agencias'            AS tabela, count(*) AS registros FROM raw.agencias
UNION ALL SELECT 'clientes',            count(*) FROM raw.clientes
UNION ALL SELECT 'colaboradores',       count(*) FROM raw.colaboradores
UNION ALL SELECT 'colaborador_agencia', count(*) FROM raw.colaborador_agencia
UNION ALL SELECT 'contas',              count(*) FROM raw.contas
UNION ALL SELECT 'propostas_credito',   count(*) FROM raw.propostas_credito
UNION ALL SELECT 'transacoes',          count(*) FROM raw.transacoes
 ORDER BY 1;

\echo ''
\echo '== Ultima ingestao por camada/entidade =='
SELECT camada, entidade, status, registros, data_referencia, registrado_em
  FROM meta.vw_ultima_ingestao
 ORDER BY camada, entidade;
