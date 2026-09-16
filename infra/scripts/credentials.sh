#!/usr/bin/env bash
# Mostra as credenciais geradas localmente (nunca versionadas).

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

TFVARS="${TF_DIR}/terraform.tfvars"
[ -f "$TFVARS" ] || die "Credenciais ainda nao geradas. Rode: make up"

valor() { grep -E "^\s*$1\s*=" "$TFVARS" | head -1 | cut -d'"' -f2; }

cat <<EOF
Airflow  http://localhost:18080
  usuario  $(valor airflow_admin_user)
  senha    $(valor airflow_admin_password)

MinIO    http://localhost:19001
  access key  $(valor minio_root_user)
  secret key  $(valor minio_root_password)

PostgreSQL (DW)  localhost:15432 / banvic_dw
  usuario  $(valor postgres_user)
  senha    $(valor postgres_password)
EOF
