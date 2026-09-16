#!/usr/bin/env bash
# Constroi as imagens do projeto e carrega no cluster kind.
#
# O kind nao enxerga o daemon local do Docker, entao cada imagem precisa ser
# explicitamente carregada nos nos ("kind load docker-image").

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require docker kind

AIRFLOW_IMAGE="${AIRFLOW_IMAGE:-banvic/airflow:local}"
MELTANO_IMAGE="${MELTANO_IMAGE:-banvic/meltano:local}"

cd "$REPO_ROOT"

log "Build da imagem do Airflow ($AIRFLOW_IMAGE)"
docker build -f images/airflow/Dockerfile -t "$AIRFLOW_IMAGE" .

log "Build da imagem do Meltano ($MELTANO_IMAGE)"
docker build -f images/meltano/Dockerfile -t "$MELTANO_IMAGE" .

log "Carregando imagens no cluster '$CLUSTER_NAME'"
kind load docker-image "$AIRFLOW_IMAGE" --name "$CLUSTER_NAME"
kind load docker-image "$MELTANO_IMAGE" --name "$CLUSTER_NAME"

log "Imagens disponiveis no no:"
docker exec "$KIND_NODE" crictl images 2>/dev/null | grep -E 'banvic|IMAGE' || true
