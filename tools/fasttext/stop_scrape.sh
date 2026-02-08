#!/bin/bash
set -euo pipefail
PID_FILE="$(cd "$(dirname "$0")" && pwd)/scrape.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  echo "Stopping scraper PID $PID..."
  kill "$PID" || true
  rm -f "$PID_FILE"
  echo "Stopped."
else
  echo "No PID file found at $PID_FILE. Trying pkill..."
  pkill -f scrape_build.py || echo "No running scraper found."
fi
