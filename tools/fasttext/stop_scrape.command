#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
osascript <<EOF
tell application "Terminal"
  activate
  do script "cd '$DIR' && chmod +x ./stop_scrape.sh && ./stop_scrape.sh"
end tell
EOF
