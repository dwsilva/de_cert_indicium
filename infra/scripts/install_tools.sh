#!/usr/bin/env bash
# Instala kubectl, kind, helm e terraform em ~/.local/bin (sem sudo).
# Util em WSL/Ubuntu limpo, onde normalmente so existe o Docker.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require curl python3

KUBECTL_VERSION="${KUBECTL_VERSION:-v1.31.0}"
KIND_VERSION="${KIND_VERSION:-v0.24.0}"
HELM_VERSION="${HELM_VERSION:-v3.16.2}"
TERRAFORM_VERSION="${TERRAFORM_VERSION:-1.9.8}"

BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *) die "Arquitetura nao suportada: $ARCH" ;;
esac

mkdir -p "$BIN_DIR"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

instalar_kubectl() {
  [ -x "$BIN_DIR/kubectl" ] && { log "kubectl ja instalado"; return; }
  log "Instalando kubectl $KUBECTL_VERSION"
  curl -sL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" -o "$BIN_DIR/kubectl"
  chmod +x "$BIN_DIR/kubectl"
}

instalar_kind() {
  [ -x "$BIN_DIR/kind" ] && { log "kind ja instalado"; return; }
  log "Instalando kind $KIND_VERSION"
  curl -sL "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-${ARCH}" -o "$BIN_DIR/kind"
  chmod +x "$BIN_DIR/kind"
}

instalar_helm() {
  [ -x "$BIN_DIR/helm" ] && { log "helm ja instalado"; return; }
  log "Instalando helm $HELM_VERSION"
  curl -sL "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz" -o "$TMP/helm.tgz"
  tar -xzf "$TMP/helm.tgz" -C "$TMP"
  install -m 0755 "$TMP/linux-${ARCH}/helm" "$BIN_DIR/helm"
}

instalar_terraform() {
  [ -x "$BIN_DIR/terraform" ] && { log "terraform ja instalado"; return; }
  log "Instalando terraform $TERRAFORM_VERSION"
  curl -sL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${ARCH}.zip" -o "$TMP/tf.zip"
  python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extract('terraform', sys.argv[2])" "$TMP/tf.zip" "$BIN_DIR"
  chmod +x "$BIN_DIR/terraform"
}

instalar_kubectl
instalar_kind
instalar_helm
instalar_terraform

echo
case ":$PATH:" in
  *":$BIN_DIR:"*) log "Ferramentas prontas em $BIN_DIR" ;;
  *) warn "Adicione ao seu shell:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac
