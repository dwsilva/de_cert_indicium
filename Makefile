SHELL := /bin/bash
SCRIPTS := infra/scripts
NAMESPACE ?= banvic
DAG ?= banvic_erp_ingestao
SCHEDULER := deploy/airflow-scheduler

.DEFAULT_GOAL := help

.PHONY: help tools data cluster seed images infra up run-dag status verify datalake credenciais logs dw test lint down clean

help: ## Lista os alvos disponiveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[1;34m%-14s\033[0m %s\n", $$1, $$2}'

tools: ## Instala kubectl, kind, helm e terraform em ~/.local/bin
	@$(SCRIPTS)/install_tools.sh

data: ## Expande banvic_data2026.zip na landing zone local
	@$(SCRIPTS)/prepare_data.sh

cluster: ## Cria o cluster Kubernetes local (kind)
	@$(SCRIPTS)/cluster_up.sh

seed: ## Publica os arquivos de origem dentro do no do cluster
	@$(SCRIPTS)/seed_landing.sh

images: ## Constroi e carrega as imagens do Airflow e do Meltano
	@$(SCRIPTS)/build_images.sh

infra: ## Aplica a infraestrutura com Terraform
	@$(SCRIPTS)/apply_infra.sh

up: ## Sobe o ambiente completo do zero
	@$(SCRIPTS)/bootstrap.sh

run-dag: ## Ativa e dispara a DAG de ingestao
	@kubectl exec -n $(NAMESPACE) $(SCHEDULER) -c scheduler -- airflow dags unpause $(DAG)
	@kubectl exec -n $(NAMESPACE) $(SCHEDULER) -c scheduler -- airflow dags trigger $(DAG)

status: ## Mostra as ultimas execucoes da DAG
	@kubectl exec -n $(NAMESPACE) $(SCHEDULER) -c scheduler -- airflow dags list-runs -d $(DAG) --no-backfill | head -20

verify: ## Confere o que chegou no Data Warehouse
	@kubectl exec -i -n $(NAMESPACE) postgres-dw-0 -- sh -c \
		'PGPASSWORD=$$POSTGRES_PASSWORD psql -X -U $$POSTGRES_USER -d $$POSTGRES_DB -f -' \
		< sql/verificacao.sql

datalake: ## Lista os objetos gravados no MinIO
	@kubectl exec -i -n $(NAMESPACE) $(SCHEDULER) -c scheduler -- python - \
		< infra/scripts/list_datalake.py 2>/dev/null

credenciais: ## Exibe as credenciais geradas localmente
	@$(SCRIPTS)/credentials.sh

logs: ## Acompanha o log do scheduler
	@kubectl logs -n $(NAMESPACE) -f $(SCHEDULER) -c scheduler

dw: ## Abre um psql no Data Warehouse
	@kubectl exec -n $(NAMESPACE) -it postgres-dw-0 -- sh -c \
		'PGPASSWORD=$$POSTGRES_PASSWORD psql -U $$POSTGRES_USER -d $$POSTGRES_DB'

test: ## Roda os testes das DAGs dentro da imagem do Airflow
	@docker run --rm --entrypoint pytest \
		-v "$(CURDIR)/tests:/opt/airflow/tests:ro" \
		-e AIRFLOW__CORE__LOAD_EXAMPLES=False \
		banvic/airflow:local /opt/airflow/tests -q

lint: ## Valida a formatacao dos arquivos Terraform
	@terraform -chdir=infra/terraform fmt -check -recursive
	@terraform -chdir=infra/terraform validate

down: ## Destroi o ambiente (cluster kind)
	@$(SCRIPTS)/teardown.sh

clean: ## Destroi tudo, inclusive o estado do Terraform
	@$(SCRIPTS)/teardown.sh --terraform
	@rm -rf data/landing
