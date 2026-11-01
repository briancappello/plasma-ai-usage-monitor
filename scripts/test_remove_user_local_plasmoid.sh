#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
FAKE_HOME="$(mktemp -d)"
trap 'rm -rf "$FAKE_HOME"' EXIT
unset XDG_DATA_HOME

# No user-local copy: succeeds and does nothing.
HOME="$FAKE_HOME" bash "$ROOT_DIR/scripts/remove_user_local_plasmoid.sh"

# A user-local copy is removed; other plasmoids are left alone.
target="$FAKE_HOME/.local/share/plasma/plasmoids/com.github.loofi.aiusagemonitor"
other="$FAKE_HOME/.local/share/plasma/plasmoids/org.example.other"
mkdir -p "$target/contents/ui" "$other"
echo '{}' > "$target/metadata.json"
HOME="$FAKE_HOME" bash "$ROOT_DIR/scripts/remove_user_local_plasmoid.sh" >/dev/null

[[ ! -e "$target" ]] || { echo "user-local plasmoid was not removed" >&2; exit 1; }
[[ -d "$other" ]] || { echo "unrelated plasmoid was removed" >&2; exit 1; }
