#!/bin/bash
# Double-clickable wrapper to start the scraper (macOS). Runs run_scrape.sh in new terminal window.
DIR="$(cd "$(dirname "$0")" && pwd)"
osascript <<EOF
tell application "Terminal"
  activate
  do script "cd '$DIR'/.. && chmod +x ./tools/fasttext/run_scrape.sh && ./tools/fasttext/run_scrape.sh"
end tell
EOF
