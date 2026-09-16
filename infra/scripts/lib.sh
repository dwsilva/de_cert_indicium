#!/usr/bin/env bash
# Funcoes compartilhadas pelos scripts de infraestrutura.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

CLUSTER_NAME="${CLUSTER_NAME:-banvic}"
KIND_NODE="${CLUSTER_NAME}-control-plane"
NAMESPACE="${NAMESPACE:-banvic}"
KIND_NODE_IMAGE="${KIND_NODE_IMAGE:-kindest/node:v1.31.0}"
LANDING_DIR="${REPO_ROOT}/data/landing"
LANDING_NODE_DIR="/mnt/banvic/landing"
TF_DIR="${REPO_ROOT}/infra/terraform"
SOURCE_ZIP="${SOURCE_ZIP:-${REPO_ROOT}/banvic_data2026.zip}"

export CLUSTER_NAME KIND_NODE NAMESPACE KIND_NODE_IMAGE LANDING_DIR LANDING_NODE_DIR TF_DIR SOURCE_ZIP

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

require() {
  for bin in "$@"; do
    command -v "$bin" >/dev/null 2>&1 || die "Comando '$bin' nao encontrado no PATH. Veja o README (pre-requisitos)."
  done
}
