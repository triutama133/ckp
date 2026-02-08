#!/bin/bash
# Run consumer-focused scraper in background, create venv if missing, install deps, and save PID + log.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"

# ensure venv
if [ ! -d ".venv" ]; then
  echo "Creating python venv at .venv..."
  python3 -m venv .venv
fi

echo "Activating venv..."
# shellcheck disable=SC1091
. .venv/bin/activate

echo "Installing python deps (if needed)..."
.venv/bin/python -m pip install --upgrade pip
REQ_FILE="$ROOT_DIR/tools/fasttext/requirements.txt"
if [ -f "$REQ_FILE" ]; then
  .venv/bin/python -m pip install -r "$REQ_FILE" || true
else
  echo "Warning: requirements file not found at $REQ_FILE; skipping install." >&2
fi

OUT_FILE="data/fasttext/train_financial_mgmt_html.txt"
LOG_FILE="tools/fasttext/scrape_finlog.log"
PID_FILE="tools/fasttext/scrape.pid"

mkdir -p $(dirname "$OUT_FILE")
mkdir -p $(dirname "$LOG_FILE")

echo "Starting scraper (background). Output -> $OUT_FILE" | tee -a "$LOG_FILE"
nohup .venv/bin/python tools/fasttext/scrape_build.py \
  --manifest tools/fasttext/sources_manifest.json \
  --out "$OUT_FILE" \
  --limit-per-site 100 \
  > "$LOG_FILE" 2>&1 &
SCRAPE_PID=$!
echo $SCRAPE_PID > "$PID_FILE"
echo "Scraper started with PID $SCRAPE_PID. Log: $LOG_FILE"
echo "Use 'tools/fasttext/stop_scrape.command' or 'tools/fasttext/stop_scrape.sh' to stop."

exit 0
