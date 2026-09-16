# Apresentação final — BanVic

Conteúdo dos slides da apresentação técnica. Um bloco por slide.

---

## 1. Capa

**BanVic — Plataforma de Ingestão de Dados**
Certificação Data Engineer · Indicium

POC de infraestrutura e pipeline ELT para tirar o banco das planilhas.

---

## 2. O problema

- 100 colaboradores, operação nacional, análises feitas em planilha e apresentação.
- Dados de ERP, CRM e marketing espalhados, sem ambiente centralizado.
- A equipe do André faz análise manual — com o risco que isso carrega.
- O piloto do Lucas (dados de crédito) precisa de base confiável para provar valor.

**O que a POC resolve:** um caminho automatizado, reprodutível e auditável do ERP até um
ambiente único de consulta.

---

## 3. Escopo da entrega

Dentro:

- Infraestrutura como código de todo o ambiente
- Pipeline de ingestão das 7 tabelas do ERP
- Orquestração, tratamento de falha e idempotência
- Documentação técnica e demonstração funcional

Fora (etapas seguintes da jornada):

- Camada de transformação (dbt), dashboards e modelos analíticos

---

## 4. Arquitetura

```
Sistema legado            Cluster Kubernetes (kind)                 Consumo
--------------            -----------------------------------       ---------
CSVs do ERP  ──────────>  PV/PVC landing (somente leitura)
                                   │
                          Airflow (KubernetesExecutor)
                                   │
                    ┌──────────────┴──────────────┐
                    ▼                             ▼
             MinIO — Data Lake            Meltano ──> PostgreSQL
             raw particionado                       schema raw     ─────>  dbt / BI
                    │                             │
                    └────────> meta.ingestion_log ┘
```

Provisionamento inteiro em Terraform: namespace, Secrets, volumes, PostgreSQL, MinIO e o release
Helm do Airflow.

---

## 5. Stack e por quê

| Camada | Escolha | Motivo |
|---|---|---|
| Cluster | kind | Sobe em container, leve, publica portas do nó direto no host |
| IaC | Terraform | Um `apply` recria o ambiente inteiro; estado explícito |
| Orquestração | Airflow 2.10 + KubernetesExecutor | Cada task é um pod; sem Celery/Redis para manter |
| Ingestão | Meltano (`tap-csv` → `target-postgres`) | Padrão Singer, configuração declarativa, MERGE por chave |
| Data Lake | MinIO | API S3, mesma interface da nuvem |
| DW | PostgreSQL 16 | Destino analítico simples e conhecido pelo time |

---

## 6. Estratégia de ingestão

**ELT: carrega primeiro, transforma depois.**

Dois destinos, propósitos diferentes:

- **Data Lake** — cópia byte a byte, particionada por data de referência.
  `raw/erp/<tabela>/data_referencia=<ds>/<tabela>.csv`
  Registro imutável do que foi recebido; permite reprocessar qualquer data sem voltar ao ERP.

- **Data Warehouse** — schema `raw` carregado pelo Meltano, com chave primária declarada por
  tabela e colunas `_sdc_*` de rastreabilidade.

**Idempotência** vem de dois pontos: a partição do Data Lake é sobrescrita e o `target-postgres`
faz `MERGE` em vez de `INSERT`. Reprocessar não duplica.

---

## 7. A DAG

```
inicio → aguardar_fontes (7 sensores) → preparar_dw
                                            ├─ carga_datalake (7 uploads)
                                            └─ carga_dw (Meltano em pod dedicado)
                                                   └─ validacao_dw (7 validações)
                                                          └─ registrar_execucao → fim
```

- Agendada para 04:35, `catchup=False`, `max_active_runs=1`
- Ramos paralelos onde não há dependência real; fan-in no registro de auditoria
- Sensores garantem que nada comece com arquivo faltando

---

## 8. Resiliência

| Situação | Tratamento |
|---|---|
| Pod demora a subir, banco reiniciando | `retries=3` com backoff exponencial, teto de 10 min |
| Arquivo ausente ou vazio | `AirflowFailException` — falha imediata, sem gastar retry |
| Contagem divergente, chave nula ou duplicada | Validação por tabela derruba a execução |
| Task travada | `execution_timeout` de 30 min (45 min no Meltano) |
| Pod destruído com o log dentro | Log remoto no MinIO |
| Falha em produção | `on_failure_callback` grava status `FALHA` em `meta.ingestion_log` |

Pods que falham não são removidos — ficam disponíveis para `kubectl logs` e `describe`.

---

## 9. Segurança e segredos

1. Senhas geradas na primeira execução por `openssl rand`, em arquivo fora do versionamento.
2. Terraform declara as variáveis como `sensitive` e cria Secrets do Kubernetes.
3. Pods consomem por `envFrom: secretRef`.
4. Connections do Airflow chegam como `AIRFLOW_CONN_*` — não ficam no banco nem são digitadas na interface.
5. `meltano.yml` referencia nomes de variáveis, nunca valores.

**Quem clona o repositório não recebe segredo nenhum.**

---

## 10. Resultado

7 tabelas, 76.206 registros, em duas camadas:

| Tabela | Registros |
|---|---|
| agencias | 10 |
| clientes | 998 |
| colaboradores | 100 |
| colaborador_agencia | 100 |
| contas | 999 |
| propostas_credito | 2.000 |
| transacoes | 71.999 |

Contagem conferida automaticamente contra a origem a cada execução.

---

## 11. Próximos passos

- **dbt** sobre o schema `raw` — tipagem, padronização e modelo dimensional
- **Dashboard comercial** para a área da Camila: transações por cliente, base ativa, sinais de churn
- **Ranking de alavancas** para a CEO: com transações, contas, propostas e agências no mesmo
  lugar, a pergunta vira consulta
- **Observabilidade** com Prometheus e Grafana sobre o exporter StatsD já ativo
- **Ingestão incremental** quando a origem deixar de ser arquivo e passar a ser o banco do ERP

---

## 12. Demonstração

`make up` → `make run-dag` → `make verify` → `make datalake`
