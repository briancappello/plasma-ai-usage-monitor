#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CALLS="$(mktemp)"
trap 'rm -f "$CALLS"' EXIT
export CALLS

systemctl() {
  printf 'systemctl %s\n' "$*" >>"$CALLS"
  case "$*" in
    '--user show plasma-plasmashell.service --property=LoadState --value')
      printf 'loaded\n' ;;
    '--user show plasma-kded6.service --property=ActiveState --value')
      printf '%s\n' "${KDED_STATE:-active}" ;;
    '--user restart plasma-kded6.service')
      return "${KDED_RESTART_STATUS:-0}" ;;
    '--user restart plasma-plasmashell.service')
      printf 'managed restart\n'
      return "${RESTART_STATUS:-0}" ;;
    *) return 99 ;;
  esac
}
# kded6 answers unless KDED_HUNG=1; once restarted it answers again.
timeout() { shift; "$@"; }
qdbus6() {
  printf 'qdbus6 %s\n' "$*" >>"$CALLS"
  if [[ "${KDED_HUNG:-0}" == 1 ]] && ! grep -q 'restart plasma-kded6' "$CALLS"; then
    return 124
  fi
}
kquitapp6() { printf 'Unexpected unmanaged shutdown\n' >&2; return 99; }
export -f systemctl timeout qdbus6 kquitapp6

reload() { : >"$CALLS"; bash "$ROOT_DIR/scripts/reload_plasma.sh"; }
fail() { printf '%s\n' "$1" >&2; exit 1; }

# Healthy kded6: plasmashell restarts, kded6 is left alone.
output=$(reload)
[[ "$output" == *'managed restart'* ]] || fail 'plasmashell was not restarted'
[[ "$output" != *'PID '* ]] || fail 'used the unmanaged path'
! grep -q 'restart plasma-kded6' "$CALLS" || fail 'restarted a healthy kded6'

# Hung kded6: restart it BEFORE plasmashell, or the new shell blocks on D-Bus.
output=$(KDED_HUNG=1 reload)
[[ "$output" == *'managed restart'* ]] || fail 'plasmashell was not restarted after kded6 recovery'
kded_line=$(grep -n 'restart plasma-kded6' "$CALLS" | cut -d: -f1 || true)
shell_line=$(grep -n 'restart plasma-plasmashell' "$CALLS" | cut -d: -f1 || true)
[[ -n "$kded_line" && "$kded_line" -lt "$shell_line" ]] || fail 'hung kded6 not restarted before plasmashell'

# kded6 stays hung: keep the running shell instead of starting one that blocks.
if KDED_HUNG=1 KDED_RESTART_STATUS=1 reload >/dev/null 2>&1; then
  fail 'unrecoverable kded6 must not report success'
fi
! grep -q 'restart plasma-plasmashell' "$CALLS" || fail 'restarted plasmashell while kded6 is hung'

# kded6 not running: nothing to probe.
KDED_STATE=inactive reload >/dev/null
! grep -q 'qdbus6' "$CALLS" || fail 'probed an inactive kded6'

# A failed plasmashell restart must not report success.
if RESTART_STATUS=1 reload >/dev/null; then
  fail 'A failed service restart must not report success'
fi
printf 'Plasma reload checks passed\n'
