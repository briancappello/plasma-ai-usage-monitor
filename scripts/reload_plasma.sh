#!/usr/bin/env bash
set -euo pipefail

KDED_TIMEOUT_SECONDS=5

# Arch ships qdbus6, Fedora ships qdbus-qt6.
QDBUS=""
for candidate in qdbus6 qdbus-qt6 qdbus; do
  if command -v "$candidate" >/dev/null 2>&1; then
    QDBUS="$candidate"
    break
  fi
done

kded_responds() {
  timeout "$KDED_TIMEOUT_SECONDS" "$QDBUS" org.kde.kded6 /kded org.kde.kded6.loadedModules >/dev/null 2>&1
}

# A fresh plasmashell blocks on D-Bus calls to kded6 at startup. If kded6 is
# alive but hung, the panels never load, so recover it before the restart.
ensure_kded_responsive() {
  command -v systemctl >/dev/null 2>&1 || return 0
  [[ -n "$QDBUS" ]] || return 0
  [[ "$(systemctl --user show plasma-kded6.service --property=ActiveState --value 2>/dev/null)" == "active" ]] || return 0
  kded_responds && return 0

  echo "kded6 is not responding on D-Bus; restarting plasma-kded6.service..."
  if systemctl --user restart plasma-kded6.service && kded_responds; then
    echo "kded6 recovered."
    return 0
  fi

  echo "kded6 is still not responding. plasmashell was NOT restarted, so the current panels stay up." >&2
  echo "Check: journalctl --user -u plasma-kded6.service" >&2
  return 1
}

ensure_kded_responsive

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
