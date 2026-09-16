#!/usr/bin/env bash
# Gera infra/terraform/terraform.tfvars com credenciais aleatorias.
#
# O arquivo fica fora do versionamento (.gitignore). Nenhuma senha do projeto
# existe em codigo: elas nascem aqui, viram Secret do Kubernetes via Terraform
# e chegam aos pods apenas como variavel de ambiente.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require openssl

TFVARS="${TF_DIR}/terraform.tfvars"

if [ -f "$TFVARS" ]; then
  log "terraform.tfvars ja existe - mantendo as credenciais atuais."
  exit 0
fi

# Senhas em hexadecimal: seguras e livres de caracteres que exigiriam escape
# dentro das connection strings.
rand() { openssl rand -hex "${1:-16}"; }

# Fernet key = 32 bytes em base64 url-safe.
fernet() { openssl rand -base64 32 | tr '+/' '-_'; }

log "Gerando credenciais em $TFVARS"
umask 077
cat > "$TFVARS" <<EOF
# Gerado automaticamente por infra/scripts/gen_secrets.sh
# NAO versionar este arquivo.

postgres_user     = "banvic"
postgres_password = "$(rand 16)"

minio_root_user     = "banvic$(rand 4)"
minio_root_password = "$(rand 20)"

airflow_admin_user           = "admin"
airflow_admin_password       = "$(rand 12)"
airflow_webserver_secret_key = "$(rand 32)"
airflow_fernet_key           = "$(fernet)"
EOF

log "Credenciais geradas. Consulte com: make credenciais"
