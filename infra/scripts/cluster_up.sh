#!/usr/bin/env bash
# Cria (ou reaproveita) o cluster Kubernetes local com kind.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require docker kind kubectl

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER_NAME"; then
  log "Cluster '$CLUSTER_NAME' ja existe - reaproveitando."
else
  log "Criando cluster kind '$CLUSTER_NAME' ($KIND_NODE_IMAGE)"
  kind create cluster \
    --name "$CLUSTER_NAME" \
    --image "$KIND_NODE_IMAGE" \
    --config "${REPO_ROOT}/infra/kind/cluster.yaml" \
    --wait 180s
fi

kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null
log "Contexto ativo: $(kubectl config current-context)"
kubectl get nodes
