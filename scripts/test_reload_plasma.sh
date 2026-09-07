#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

systemctl() {
  case "$*" in
    '--user show plasma-plasmashell.service --property=LoadState --value')
      printf 'loaded\n' ;;
    '--user restart plasma-plasmashell.service')
      printf 'managed restart\n'
      return "${RESTART_STATUS:-0}" ;;
    *) return 99 ;;
  esac
}
kquitapp6() { printf 'Unexpected unmanaged shutdown\n' >&2; return 99; }
export -f systemctl kquitapp6

output=$(bash "$ROOT_DIR/scripts/reload_plasma.sh")
[[ "$output" == *'managed restart'* ]]
[[ "$output" != *'PID '* ]]
if RESTART_STATUS=1 bash "$ROOT_DIR/scripts/reload_plasma.sh" >/dev/null; then
  printf 'A failed service restart must not report success\n' >&2
  exit 1
fi
printf 'Plasma reload checks passed\n'
