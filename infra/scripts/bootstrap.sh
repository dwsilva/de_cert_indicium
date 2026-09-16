#!/usr/bin/env bash
# Sobe o ambiente completo do zero, na ordem correta.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SCRIPTS="${REPO_ROOT}/infra/scripts"

"${SCRIPTS}/prepare_data.sh"
"${SCRIPTS}/cluster_up.sh"
"${SCRIPTS}/seed_landing.sh"
"${SCRIPTS}/build_images.sh"
"${SCRIPTS}/apply_infra.sh"

cat <<EOF

--------------------------------------------------------------------------
Ambiente pronto.

  Airflow ........ http://localhost:18080
  MinIO console .. http://localhost:19001
  Data Warehouse . localhost:15432  (banco banvic_dw)

Credenciais: make credenciais
Disparar o pipeline: make run-dag
--------------------------------------------------------------------------
EOF
