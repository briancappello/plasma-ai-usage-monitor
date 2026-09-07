#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Settings controls must edit cfg_* properties, not the running applet's configuration.
if grep -nE 'plasmoid\.configuration\.[[:alnum:]_]+[[:space:]]*=[^=]' "$ROOT_DIR"/package/contents/ui/config*.qml; then
  printf 'Settings pages must stage configuration changes until Apply/OK.\n' >&2
  exit 1
fi
