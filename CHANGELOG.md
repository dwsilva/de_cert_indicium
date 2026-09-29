# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/);
versionamento conforme [SemVer](https://semver.org/lang/pt-BR/).

## [v1.0.0] - 2026-09-16

Primeira versão completa da POC de ingestão de dados do BanVic, entregue como
trabalho da Certificação Data Engineer da Indicium.

### Infraestrutura

- Cluster Kubernetes local com kind, nó único, com as portas do Airflow, do MinIO
  e do PostgreSQL publicadas no host.
- Módulo Terraform provisionando namespace, Secrets, PersistentVolumes,
  PostgreSQL 16, MinIO com criação dos buckets e o release Helm do Airflow.
- Airflow 2.10.5 com KubernetesExecutor, banco de metadados no PostgreSQL do
  próprio projeto e logs remotos no MinIO.
- Imagens próprias do Airflow (com as DAGs embarcadas) e do Meltano (com os
  plugins instalados em tempo de build).

### Ingestão

- Projeto Meltano com `tap-csv` e `target-postgres` declarados como custom
  plugins, sem dependência do Meltano Hub em tempo de execução.
- Chave primária declarada por tabela e `load_method: upsert`, o que faz o
  carregamento ser idempotente.
- Colunas `_sdc_*` de rastreabilidade habilitadas.
- Camada raw do Data Lake particionada por data de referência.

### Orquestração

- DAG `banvic_erp_ingestao` com sensores de disponibilidade, preparo do destino,
  cargas paralelas no Data Lake e no Data Warehouse, validação por tabela e
  registro de auditoria.
- Agendamento diário às 04:35 (America/Sao_Paulo), sem catchup e com execução
  única simultânea.

### Monitoramento e resiliência

- Retries com backoff exponencial para falha transitória e `AirflowFailException`
  para erro de dado.
- Validação de contagem, chave nula e chave duplicada contra a origem.
- Auditoria em `meta.ingestion_log` e view `meta.vw_ultima_ingestao`.
- `on_failure_callback` em todas as tasks e exporter StatsD ativo.

### Segurança

- Credenciais geradas na primeira execução, fora do versionamento, distribuídas
  como Secrets do Kubernetes.
- Connections do Airflow injetadas por variável de ambiente.

### Automação e documentação

- Makefile como interface única de operação.
- 13 testes estruturais das DAGs, executados dentro da imagem do Airflow.
- CI com validação de Terraform, ShellCheck, testes das DAGs, build do Meltano e
  varredura de credenciais versionadas.
- README com diagrama da arquitetura, passo a passo e estratégia de ingestão;
  documento de arquitetura e apresentação final em `docs/`.

[v1.0.0]: https://github.com/dwsilva/de_cert_indicium/releases/tag/v1.0.0
