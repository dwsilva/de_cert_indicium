#!/usr/bin/env bash
# Remove o ambiente. Por padrao destroi apenas o cluster (mais rapido).
#   ./teardown.sh --terraform  -> executa terraform destroy antes

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require kind

if [ "${1:-}" = "--terraform" ] && [ -d "${TF_DIR}/.terraform" ]; then
  log "terraform destroy"
  (cd "$TF_DIR" && terraform destroy -input=false -auto-approve) || warn "destroy falhou; seguindo para a remocao do cluster"
fi

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "Removendo cluster '$CLUSTER_NAME'"
  kind delete cluster --name "$CLUSTER_NAME"
else
  log "Cluster '$CLUSTER_NAME' nao esta ativo."
fi

rm -f "${TF_DIR}/terraform.tfstate" "${TF_DIR}/terraform.tfstate.backup"
log "Ambiente removido."
