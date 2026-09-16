# Roteiro do vídeo

Apresentação técnica de **3 a 5 minutos**. O roteiro abaixo fecha em **4min30**, deixando
folga para respirar e para algum imprevisto.

As falas estão escritas para serem lidas em voz alta. Não precisa decorar — precisa soar
natural, então adapte as palavras, mas mantenha o tamanho de cada bloco.

---

## Antes de gravar

**Ambiente**

```bash
make up          # deixe o ambiente de pé ANTES de gravar
make run-dag     # rode a DAG uma vez, para já existir histórico verde na interface
make credenciais # deixe a senha do Airflow copiada
```

**Telas abertas, nesta ordem de abas**

1. Navegador: Airflow logado em <http://localhost:18080>, já na tela da DAG
2. Navegador, segunda aba: console do MinIO em <http://localhost:19001>, já logado
3. Terminal, fonte grande (16pt ou mais), janela limpa
4. Editor com `dags/banvic_erp_ingestao.py` aberto
5. README aberto na seção do diagrama

**Higiene de gravação**

- Modo "não perturbe" ligado, notificações fechadas
- Terminal com histórico limpo (`clear`)
- Zoom do navegador em 110–125%: o Graph View do Airflow fica pequeno na gravação
- Grave em 1080p

---

## A questão do tempo

Dois trechos são mais lentos que o vídeo permite. Resolva assim:

| Trecho | Duração real | O que fazer |
|---|---|---|
| `make up` do zero | 5 a 8 min | Não grave a espera. Mostre o comando, fale por cima, e corte para o resultado (`kubectl get pods`) |
| Execução da DAG | ~1min45 | Dispare, mostre o Graph View preenchendo por uns 15s, e corte para a execução já concluída |

Os dois cortes são legítimos e esperados numa apresentação técnica. O que o avaliador precisa
ver é o comando, o resultado e a DAG verde — não o relógio andando.

---

## Bloco 1 — Abertura e arquitetura · 0:00 a 0:45

**Tela:** diagrama da arquitetura no README.

> "O BanVic hoje faz todas as análises em planilha, com os dados do ERP presos no sistema de
> origem. A proposta é uma POC que centraliza esses dados num ambiente reprodutível.
>
> A infraestrutura inteira é código: um cluster Kubernetes local com kind, provisionado por
> Terraform, rodando Airflow, PostgreSQL e MinIO.
>
> O dado sai dos arquivos do ERP e cai em duas camadas. Uma cópia bruta no Data Lake, que é o
> registro imutável do que foi recebido. E o schema `raw` no Data Warehouse, que é o que o
> analista consulta. A ingestão é feita com Meltano."

*Enquanto fala, passe o cursor no diagrama: origem → Airflow → MinIO e PostgreSQL.*

---

## Bloco 2 — Deploy do ambiente · 0:45 a 1:30

**Tela:** terminal.

```bash
make up
```

*Deixe rolar uns segundos e fale por cima:*

> "Um comando sobe tudo: expande os dados, cria o cluster, publica os arquivos dentro do nó,
> constrói as imagens do Airflow e do Meltano e aplica o Terraform.
>
> As senhas não existem no repositório. Elas são geradas na primeira execução pelo `openssl`,
> viram Secret do Kubernetes e chegam aos pods só como variável de ambiente. Quem clona o
> projeto não recebe credencial nenhuma."

*Corte para o ambiente pronto:*

```bash
kubectl get pods -n banvic
```

> "Airflow com scheduler, webserver e triggerer, o PostgreSQL e o MinIO — tudo isolado num
> namespace só."

---

## Bloco 3 — A DAG no Airflow · 1:30 a 2:50

**Tela:** navegador no Airflow, Graph View da `banvic_erp_ingestao`.

> "Essa é a DAG de ingestão. Ela começa com um sensor por tabela, conferindo se o arquivo
> chegou — nada roda com fonte incompleta.
>
> Depois vem o preparo do destino, que é idempotente.
>
> Aí o fluxo abre em dois ramos paralelos: de um lado a cópia bruta para o Data Lake, do outro
> a carga do Meltano no Data Warehouse. São independentes, então rodam ao mesmo tempo.
>
> A validação só começa depois que o Meltano termina — essa é a dependência real. E tudo
> converge no registro de auditoria."

*Volte ao terminal e dispare:*

```bash
make run-dag
```

*Volte ao Airflow, mostre as tasks ficando verdes. Em paralelo, no terminal:*

```bash
kubectl get pods -n banvic
```

> "Cada task vira um pod: é o KubernetesExecutor. E o Meltano roda na imagem dele mesmo, num
> pod dedicado, disparado por um KubernetesPodOperator. As dependências das duas ferramentas
> ficam separadas."

*Corte para a execução concluída, tudo verde. Abra o log da task `carga_dw`:*

> "Esse log está vindo do MinIO. Como o pod da task é destruído no final, o log remoto é o que
> mantém o histórico acessível pela interface."

---

## Bloco 4 — Os dados no destino · 2:50 a 3:40

**Tela:** terminal.

```bash
make verify
```

> "As sete tabelas no schema `raw`, com a contagem de cada uma batendo exatamente com a
> origem — essa conferência é uma task da DAG, roda sozinha a cada execução.
>
> E embaixo a tabela de auditoria, mostrando cada camada e cada entidade da execução, com
> volume e status."

```bash
make datalake
```

> "No Data Lake, os mesmos arquivos particionados por data de referência."

*Se quiser reforçar visualmente, pule para a aba do console do MinIO e navegue até
`banvic-datalake/raw/erp/transacoes/`.*

---

## Bloco 5 — Resiliência e idempotência · 3:40 a 4:20

**Tela:** editor com `dags/banvic_erp_ingestao.py`, no bloco `DEFAULT_ARGS`.

> "Sobre tratamento de falha: todas as tasks têm retry com backoff exponencial, para o erro
> transitório — pod que demora a subir, banco reiniciando.
>
> Mas erro de dado é tratado diferente. Arquivo vazio ou contagem divergente levantam
> `AirflowFailException`, que falha na hora sem gastar retry, porque repetir não resolveria.
>
> E a execução é idempotente por dois motivos: a partição do Data Lake é sobrescrita, e o
> target do Meltano faz MERGE pela chave primária de cada tabela, em vez de INSERT."

*Se sobrar tempo, mostre a prova — dispare de novo e rode `make verify`:*

> "Mesma data, terceira execução, contagens idênticas. Nada duplicou."

---

## Bloco 6 — Fechamento · 4:20 a 4:30

**Tela:** diagrama ou Airflow verde.

> "Resumindo: infraestrutura inteira como código, ingestão idempotente com Meltano,
> orquestração com dependências explícitas e sensores, e nenhum segredo versionado. O ambiente
> sobe do zero em um comando, em qualquer máquina com Docker."

---

## Checklist de cobertura

O enunciado exige explicitamente estes três pontos no vídeo:

- [ ] **Deploy do ambiente** — Bloco 2
- [ ] **Interface do Airflow com a DAG executada com sucesso** — Bloco 3
- [ ] **Verificação final dos dados chegando no destino** — Bloco 4

E estes pesam nos critérios de avaliação:

- [ ] Gerenciamento de segredos mencionado — Bloco 2
- [ ] Dependências e uso de operadores explicados — Bloco 3
- [ ] Retries e idempotência — Bloco 5

---

## Se algo der errado ao vivo

- **DAG falhou na gravação:** os pods com falha não são removidos. `kubectl logs -n banvic <pod>`
  mostra a causa. Mas prefira regravar o bloco a debugar em vídeo.
- **Airflow não abre:** confira `kubectl get pods -n banvic` e a porta 18080.
- **Esqueceu a senha:** `make credenciais`.
