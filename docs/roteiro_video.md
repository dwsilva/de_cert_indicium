# Roteiro do vídeo (3 a 5 minutos)

Roteiro de gravação da apresentação técnica. Tempo-alvo: **4 minutos**.

## Antes de gravar

Deixar pronto para não perder tempo em tela:

```bash
make down          # garante que a demo comeca do zero
make data          # o zip ja expandido evita espera na gravacao
docker pull kindest/node:v1.31.0   # cache da imagem do no
```

Abrir três coisas: terminal, navegador em branco e o repositório no editor.
Rodar `make credenciais` antes e deixar a senha copiada.

Se preferir não gravar o `make up` inteiro (leva de 5 a 8 minutos), suba o ambiente antes,
mostre o comando e a saída final, e corte para o ambiente pronto.

---

## Bloco 1 — Contexto e arquitetura (45s)

**Tela:** diagrama do README.

> "O BanVic hoje analisa tudo em planilha. A proposta é uma POC que centraliza os dados do ERP
> em um ambiente reprodutível: Kubernetes local provisionado por Terraform, Airflow orquestrando
> e Meltano fazendo a ingestão. O dado cai em duas camadas — uma cópia bruta no Data Lake, que é
> o registro do que foi recebido, e o schema `raw` no Data Warehouse, que é o que o analista
> consulta."

Apontar no diagrama: landing zone → Airflow → MinIO e PostgreSQL.

---

## Bloco 2 — Deploy do ambiente (60s)

**Tela:** terminal.

```bash
make up
```

Enquanto roda, narrar os cinco passos:

> "Um comando faz tudo: expande os dados, cria o cluster kind, publica os arquivos dentro do nó,
> constrói as imagens do Airflow e do Meltano e aplica o Terraform. As senhas são geradas na
> hora pelo `openssl` e viram Secret do Kubernetes — não existe credencial no repositório."

Mostrar o `terraform apply` finalizando e os pods de pé:

```bash
kubectl get pods -n banvic
```

---

## Bloco 3 — A DAG rodando (90s)

**Tela:** navegador em <http://localhost:18080>, depois terminal.

```bash
make run-dag
```

Na interface, abrir a `banvic_erp_ingestao` em Graph View e narrar a estrutura:

> "Primeiro os sensores, um por tabela, conferindo se o arquivo chegou. Depois o preparo do
> destino. Aí o fluxo abre em dois ramos paralelos: a cópia bruta para o Data Lake e a carga do
> Meltano no Data Warehouse. A validação só começa depois do Meltano, e tudo converge no
> registro de auditoria."

Mostrar os pods de task sendo criados em tempo real:

```bash
kubectl get pods -n banvic -w
```

> "Cada task é um pod. O Meltano roda na própria imagem, com os plugins instalados no build."

Voltar à interface e mostrar tudo em verde. Abrir o log de `carga_dw`.

> "O log está sendo lido do MinIO. Como o pod é destruído no fim da task, o log remoto é o que
> mantém o histórico acessível."

---

## Bloco 4 — Verificação dos dados (60s)

**Tela:** terminal.

```bash
make verify
```

> "As sete tabelas no schema `raw`, com a contagem batendo com a origem. E a tabela de auditoria
> mostrando cada camada e cada entidade da execução."

```bash
make datalake
```

> "No Data Lake, os arquivos particionados por data de referência."

Opcional, se sobrar tempo — mostrar o console do MinIO em <http://localhost:19001>.

---

## Bloco 5 — Resiliência e fechamento (30s)

**Tela:** `dags/banvic_erp_ingestao.py`.

> "Sobre resiliência: retries com backoff exponencial para erro transitório, e
> `AirflowFailException` para erro de dado, que não adianta repetir. A idempotência vem de dois
> pontos — a partição do Data Lake é sobrescrita e o `target-postgres` faz MERGE pela chave
> primária. Posso reprocessar a mesma data quantas vezes quiser e o resultado é o mesmo."

Rodar de novo, se der tempo:

```bash
make run-dag && make verify
```

> "Mesmas contagens. Fechando: infraestrutura como código, ingestão idempotente, orquestração
> com dependências explícitas e nenhum segredo versionado."

---

## Checklist do que precisa aparecer

- [ ] Deploy do ambiente (`make up` ou o resultado dele)
- [ ] Interface do Airflow com a DAG executada com sucesso
- [ ] Pods de task sendo criados no Kubernetes
- [ ] Dados no destino (`make verify` e `make datalake`)
- [ ] Menção a segredos, retries e idempotência
