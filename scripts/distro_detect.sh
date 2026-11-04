# shellcheck shell=bash
# Sourced by the install scripts. Sets:
#   DISTRO_FAMILY  fedora | arch | unknown  (matches ID or ID_LIKE, so Fedora
#                  Asahi Remix, Nobara, Manjaro, EndeavourOS, CachyOS... work)
#   OS_PRETTY      human-readable OS name
# os-release is read in a subshell so its variables don't leak into the caller.

OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
DISTRO_FAMILY="unknown"
OS_PRETTY="Unknown"

if [[ -f "$OS_RELEASE_FILE" ]]; then
  # shellcheck disable=SC1090
  _distro_ids="$(. "$OS_RELEASE_FILE" && printf '%s %s' "${ID:-}" "${ID_LIKE:-}")"
  # shellcheck disable=SC1090
  OS_PRETTY="$(. "$OS_RELEASE_FILE" && printf '%s' "${PRETTY_NAME:-${ID:-Unknown}}")"
  for _distro_id in $_distro_ids; do
    case "$_distro_id" in
      fedora) DISTRO_FAMILY="fedora"; break ;;
      arch) DISTRO_FAMILY="arch"; break ;;
    esac
  done
  unset _distro_ids _distro_id
fi
