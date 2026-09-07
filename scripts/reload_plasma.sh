#!/usr/bin/env bash
set -euo pipefail

echo "Reloading plasmashell..."
if command -v systemctl >/dev/null 2>&1 \
  && [[ "$(systemctl --user show plasma-plasmashell.service --property=LoadState --value 2>/dev/null)" == "loaded" ]]; then
  systemctl --user restart plasma-plasmashell.service
  echo "Plasma's user service restarted. Startup logs: journalctl --user -u plasma-plasmashell.service"
  exit 0
fi

if command -v kquitapp6 >/dev/null 2>&1; then
  kquitapp6 plasmashell || true
else
  pkill -x plasmashell || true
fi

# Give it a moment to fully exit
sleep 1

nohup plasmashell >/dev/null 2>&1 &
PLASMA_PID=$!
echo "plasmashell restarted (PID $PLASMA_PID)."
echo "Wait a few seconds for the panel to appear, then right-click to add the widget."
