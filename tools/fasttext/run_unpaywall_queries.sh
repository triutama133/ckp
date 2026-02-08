#!/usr/bin/env bash
# Helper to run build_unpaywall.py with expanded personal finance queries
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV="$REPO_ROOT/.venv/bin/python"
SCRIPT="$REPO_ROOT/tools/fasttext/build_unpaywall.py"
OUT="$REPO_ROOT/data/fasttext/train_unpaywall.txt"
QUERIES=(
  "personal finance"
  "personal finance indonesia"
  "personal finansial"
  "family financial management"
  "manajemen finansial"
  "manajemen finansial keluarga"
  "personal financial management"
  "financial planning"
  "personal financial planning"
  "family financial planning"
  "household finance"
  "household financial management"
)
QUERY_STR=$(IFS=,; echo "${QUERIES[*]}")
if [ -z "${1:-}" ]; then
  echo "Usage: $0 your@email.example [max-per-query]"
  exit 1
fi
EMAIL="$1"
MAX_PER=${2:-50}
mkdir -p "$(dirname "$OUT")"
$VENV "$SCRIPT" --queries "$QUERY_STR" --email "$EMAIL" --out "$OUT" --max-per-query $MAX_PER
