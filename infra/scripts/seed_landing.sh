#!/usr/bin/env bash
# Publica os arquivos da landing zone dentro do no do cluster.
#
# O diretorio /mnt/banvic/landing do no e a origem do PersistentVolume montado
# em modo somente leitura no Airflow e no Meltano. Usamos "docker cp" em vez de
# hostPath do Windows para funcionar igual em WSL, Linux e macOS.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require docker

[ -d "$LANDING_DIR" ] || die "Landing zone local nao existe. Rode: make data"

docker inspect "$KIND_NODE" >/dev/null 2>&1 || die "No '$KIND_NODE' nao encontrado. Rode: make cluster"

log "Copiando arquivos para ${KIND_NODE}:${LANDING_NODE_DIR}"
docker exec "$KIND_NODE" mkdir -p "$LANDING_NODE_DIR"
docker cp "${LANDING_DIR}/." "${KIND_NODE}:${LANDING_NODE_DIR}/"
docker exec "$KIND_NODE" sh -c "chmod -R a+rX '$LANDING_NODE_DIR'"

log "Conteudo da landing zone no cluster:"
docker exec "$KIND_NODE" ls -1sh "$LANDING_NODE_DIR"
