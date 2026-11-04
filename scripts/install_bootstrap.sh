#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

ASSUME_YES=false
DRY_RUN=false
INSTALL_MISSING=false

usage() {
  cat <<'USAGE'
install_bootstrap.sh - build from source and install Plasma AI Usage Monitor to /usr

Usage:
  scripts/install_bootstrap.sh [--yes] [--dry-run] [--install-missing]

Options:
  --yes               Skip interactive confirmation prompts.
  --dry-run           Print commands without executing.
  --install-missing   On Fedora or Arch, install missing build deps via doctor.
  -h, --help          Show this help.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --yes)
      ASSUME_YES=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --install-missing)
      INSTALL_MISSING=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

# shellcheck source=distro_detect.sh
source "$ROOT_DIR/scripts/distro_detect.sh"

run_cmd() {
  if [[ "$DRY_RUN" == true ]]; then
    printf '[dry-run]'
    for arg in "$@"; do
      printf ' %q' "$arg"
    done
    printf '\n'
  else
    "$@"
  fi
}

confirm_or_exit() {
  local prompt="$1"
  if [[ "$ASSUME_YES" == true ]]; then
    return 0
  fi

  read -r -p "$prompt [y/N]: " answer
  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      echo "Cancelled."
      exit 1
      ;;
  esac
}

echo "Detected $OS_PRETTY ($(uname -m)); building from source."
echo

if [[ "$INSTALL_MISSING" == true ]]; then
  run_cmd bash "$ROOT_DIR/scripts/install_doctor.sh" --install-missing
else
  run_cmd bash "$ROOT_DIR/scripts/install_doctor.sh"
fi

confirm_or_exit "Build and install from source to /usr (requires sudo)?"
run_cmd bash "$ROOT_DIR/scripts/clear_stale_cmake_cache.sh" "$ROOT_DIR/build"
run_cmd cmake -S "$ROOT_DIR" -B "$ROOT_DIR/build" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release

if command -v nproc >/dev/null 2>&1; then
  jobs="$(nproc)"
else
  jobs="4"
fi
run_cmd cmake --build "$ROOT_DIR/build" --parallel "$jobs"
run_cmd sudo cmake --install "$ROOT_DIR/build"
run_cmd bash "$ROOT_DIR/scripts/remove_user_local_plasmoid.sh"

echo
echo "Install/bootstrap complete."

# Offer plasmashell reload so widget appears immediately
if command -v plasmashell >/dev/null 2>&1; then
  if [[ "$ASSUME_YES" == true ]]; then
    echo "Reloading plasmashell to activate widget..."
    run_cmd bash "$ROOT_DIR/scripts/reload_plasma.sh"
  else
    echo
    read -r -p "Reload plasmashell now to make widget appear? [Y/n]: " reload_answer
    case "${reload_answer:-y}" in
      y|Y|yes|YES|"")
        run_cmd bash "$ROOT_DIR/scripts/reload_plasma.sh"
        ;;
      *)
        echo "Skipped. Run manually: ./scripts/reload_plasma.sh"
        ;;
    esac
  fi
fi

echo
echo "Next steps:"
echo "  1. Right-click panel → Add Widgets → search 'AI Usage Monitor'"
echo "  2. Right-click widget → Configure → add your API keys"
echo "  3. If widget still not visible, run: ./scripts/show_installed_versions.sh"
