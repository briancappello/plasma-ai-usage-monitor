#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Plasma AI Usage Monitor — Uninstall ==="
echo

# Detect what's installed
PLASMOID_ID="com.github.loofi.aiusagemonitor"
USER_PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/${PLASMOID_ID}"
SYS_PLASMOID_META="/usr/share/plasma/plasmoids/${PLASMOID_ID}/metadata.json"
SYS_MANIFEST="${ROOT_DIR}/build/install_manifest.txt"
HAS_USER_LOCAL=false
HAS_SYSTEM=false
HAS_MANIFEST=false

[[ -d "$USER_PLASMOID_DIR" ]] && HAS_USER_LOCAL=true
[[ -f "$SYS_PLASMOID_META" ]] && HAS_SYSTEM=true
[[ -f "$SYS_MANIFEST" ]] && HAS_MANIFEST=true

echo "Installed copies found:"
[[ "$HAS_USER_LOCAL" == true ]] && echo "  [user-local]  $USER_PLASMOID_DIR"
[[ "$HAS_SYSTEM" == true ]]     && echo "  [system]      /usr/share/plasma/plasmoids/${PLASMOID_ID}"

if [[ "$HAS_USER_LOCAL" == false && "$HAS_SYSTEM" == false ]]; then
  echo "  (nothing detected)"
  exit 0
fi

echo

# Remove user-local
if [[ "$HAS_USER_LOCAL" == true ]]; then
  read -r -p "Remove user-local plasmoid? [Y/n]: " answer
  case "${answer:-y}" in
    y|Y|yes|YES|"")
      kpackagetool6 --type Plasma/Applet --remove "$PLASMOID_ID"
      echo "User-local plasmoid removed."
      ;;
    *) echo "Skipped user-local removal." ;;
  esac
fi

# Remove system install
if [[ "$HAS_SYSTEM" == true ]]; then
  if [[ "$HAS_MANIFEST" == true ]]; then
    read -r -p "Remove system install (requires sudo)? [Y/n]: " answer
    case "${answer:-y}" in
      y|Y|yes|YES|"")
        sudo xargs rm -f < "$SYS_MANIFEST"
        sudo ldconfig
        echo "System install removed."
        ;;
      *) echo "Skipped system removal." ;;
    esac
  else
    echo "System install detected but no build/install_manifest.txt found."
    echo "Re-run ./install.sh first (it records the installed files), then ./uninstall.sh."
  fi
fi

echo
echo "Uninstall complete. Run ./scripts/reload_plasma.sh to refresh the panel."
