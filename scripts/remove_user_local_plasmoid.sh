#!/usr/bin/env bash
# Plasma loads the user data dir's plasmoids before /usr/share/plasma/plasmoids,
# so any user-local copy of this widget shadows the system install. The system
# install is the only supported path; remove the user-local copy if present.
set -euo pipefail

PLASMOID_ID="com.github.loofi.aiusagemonitor"
USER_PLASMOID_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/plasma/plasmoids/${PLASMOID_ID}"

[[ -e "$USER_PLASMOID_DIR" ]] || exit 0

echo "Removing user-local copy that shadows the system install: $USER_PLASMOID_DIR"
rm -rf "$USER_PLASMOID_DIR"
