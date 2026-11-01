#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XML="$ROOT_DIR/package/contents/config/main.xml"
# The panel chart defaults to Claude Code (index 0) and its weekly window.
default_of() {
  sed -n "/<entry name=\"$1\"/,/<\/entry>/s:.*<default>\(.*\)</default>.*:\1:p" "$XML"
}
fail=0
[[ "$(default_of chartToolIndex)" == "0" ]] || { echo "chartToolIndex default must be 0 (Claude Code)" >&2; fail=1; }
[[ "$(default_of chartQuotaWindow)" == "weekly" ]] || { echo "chartQuotaWindow default must be weekly" >&2; fail=1; }
exit "$fail"
