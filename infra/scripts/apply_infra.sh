#!/usr/bin/env bash
# Provisiona a stack (PostgreSQL, MinIO, Airflow) com Terraform.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require terraform kubectl

"${REPO_ROOT}/infra/scripts/gen_secrets.sh"

cd "$TF_DIR" || die "Diretorio do Terraform nao encontrado: $TF_DIR"

log "terraform init"
terraform init -input=false -upgrade >/dev/null

log "terraform apply"
terraform apply -input=false -auto-approve

log "Recursos no namespace '$NAMESPACE':"
kubectl get pods -n "$NAMESPACE"
echo
terraform output
