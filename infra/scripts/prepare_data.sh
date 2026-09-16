#!/usr/bin/env bash
# Expande o pacote de dados do ERP na landing zone local.
# Simula a chegada dos arquivos no compartilhamento do sistema legado.

source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

[ -f "$SOURCE_ZIP" ] || die "Arquivo de dados nao encontrado: $SOURCE_ZIP"

log "Expandindo $(basename "$SOURCE_ZIP") em data/landing/"
rm -rf "$LANDING_DIR"
mkdir -p "$LANDING_DIR"

if command -v unzip >/dev/null 2>&1; then
  unzip -oq "$SOURCE_ZIP" -d "$LANDING_DIR"
else
  # Fallback sem unzip instalado (o Python ja e pre-requisito do projeto).
  python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
    "$SOURCE_ZIP" "$LANDING_DIR"
fi

# O zip pode trazer os CSVs dentro de um diretorio; normaliza para a raiz.
find "$LANDING_DIR" -mindepth 2 -name '*.csv' -exec mv -f {} "$LANDING_DIR"/ \; 2>/dev/null || true
find "$LANDING_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

arquivos=$(find "$LANDING_DIR" -maxdepth 1 -name '*.csv' | wc -l)
[ "$arquivos" -gt 0 ] || die "Nenhum CSV encontrado apos a extracao."

log "$arquivos arquivo(s) disponiveis em $LANDING_DIR"
ls -1sh "$LANDING_DIR"
