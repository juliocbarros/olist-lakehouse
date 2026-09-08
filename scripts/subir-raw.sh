#!/usr/bin/env bash
# Sobe os 9 CSVs do dataset Olist para o Volume bronze.raw. Precisa rodar
# depois de `databricks bundle deploy`, já que o Volume só existe depois do
# deploy criar os schemas/volume do catálogo.
#
# Uso: scripts/subir-raw.sh <profile> [pasta_dos_csvs] [catalog]
#
# Se você rodar este script via Git Bash / WSL, caminhos do Windows com
# espaço e "&" (como "Dados & Analytics") precisam estar entre aspas, como
# no default abaixo.
set -euo pipefail

PROFILE="${1:?uso: scripts/subir-raw.sh <profile> [pasta_dos_csvs] [catalog]}"
DADOS_DIR="${2:-/c/Users/julio/OneDrive/Documentos/Dados & Analytics/Base de teste/Base_Olist/Olist_new}"
CATALOG="${3:-lakehouse_olist}"

if [ ! -d "$DADOS_DIR" ]; then
  echo "ERRO: '$DADOS_DIR' não existe ou não é uma pasta." >&2
  echo "Passe o caminho correto como segundo argumento." >&2
  exit 1
fi

# `databricks fs cp` exige o esquema dbfs: no destino, mesmo sendo um Volume
# do Unity Catalog. Sobe todos os .csv da pasta, achatados, direto para
# bronze.raw (não há subpastas erp/crm neste dataset — é um único sistema).
databricks fs cp --recursive --overwrite \
  "$DADOS_DIR" "dbfs:/Volumes/$CATALOG/bronze/raw" \
  --profile "$PROFILE"
