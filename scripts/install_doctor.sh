#!/usr/bin/env bash
set -euo pipefail

AUTO_INSTALL=false
STRICT=false

usage() {
  cat <<'USAGE'
install_doctor.sh - preflight checks for building/installing Plasma AI Usage Monitor

Usage:
  scripts/install_doctor.sh [--install-missing] [--strict]

Options:
  --install-missing  On Fedora (dnf) or Arch (pacman), install missing build dependencies.
  --strict           Exit non-zero if any warning-level runtime tool is missing.
  -h, --help         Show this help.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --install-missing)
      AUTO_INSTALL=true
      ;;
    --strict)
      STRICT=true
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

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=distro_detect.sh
source "$ROOT_DIR/scripts/distro_detect.sh"

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "missing"
  fi
}

required_cmds=(cmake g++ kpackagetool6)
warning_cmds=(plasmashell plasmawindowed)

missing_required=()
missing_warning=()
for cmd in "${required_cmds[@]}"; do
  if [[ "$(check_cmd "$cmd")" == "missing" ]]; then
    missing_required+=("$cmd")
  fi
done
for cmd in "${warning_cmds[@]}"; do
  if [[ "$(check_cmd "$cmd")" == "missing" ]]; then
    missing_warning+=("$cmd")
  fi
done

fedora_packages=(
  cmake
  extra-cmake-modules
  gcc-c++
  qt6-qtbase
  qt6-qtbase-devel
  qt6-qtdeclarative-devel
  libplasma-devel
  kf6-kwallet-devel
  kf6-ki18n-devel
  kf6-knotifications-devel
  kf6-kcoreaddons-devel
)

arch_packages=(
  cmake
  extra-cmake-modules
  gcc
  qt6-base
  qt6-declarative
  libplasma
  kwallet
  ki18n
  knotifications
  kcoreaddons
)

packages=()
installed_packages=()
missing_packages=()
install_cmd=()
if [[ "$DISTRO_FAMILY" == "fedora" ]] && command -v rpm >/dev/null 2>&1; then
  packages=("${fedora_packages[@]}")
  for pkg in "${packages[@]}"; do
    if rpm -q --whatprovides "$pkg" >/dev/null 2>&1; then
      installed_packages+=("$pkg")
    else
      missing_packages+=("$pkg")
    fi
  done
  install_cmd=(sudo dnf install -y)
elif [[ "$DISTRO_FAMILY" == "arch" ]] && command -v pacman >/dev/null 2>&1; then
  packages=("${arch_packages[@]}")
  # pacman -T prints the deps that are not satisfied (honours provides).
  mapfile -t missing_packages < <(pacman -T "${packages[@]}" || true)
  for pkg in "${packages[@]}"; do
    if [[ " ${missing_packages[*]} " != *" $pkg "* ]]; then
      installed_packages+=("$pkg")
    fi
  done
  install_cmd=(sudo pacman -S --needed)
fi

sqlite_driver_ok=false
qt_plugin_dirs=(/usr/lib64/qt6/plugins /usr/lib/qt6/plugins)
if command -v qtpaths6 >/dev/null 2>&1; then
  qt_plugin_dirs=("$(qtpaths6 --query QT_INSTALL_PLUGINS 2>/dev/null)" "${qt_plugin_dirs[@]}")
fi
for dir in "${qt_plugin_dirs[@]}"; do
  if [[ -n "$dir" && -f "$dir/sqldrivers/libqsqlite.so" ]]; then
    sqlite_driver_ok=true
    break
  fi
done

echo "=== Plasma AI Usage Monitor - Install Doctor ==="
echo "OS: $OS_PRETTY"
echo

echo "Required command checks:"
for cmd in "${required_cmds[@]}"; do
  state="$(check_cmd "$cmd")"
  printf '  - %-14s %s\n' "$cmd" "$state"
done

echo

echo "Runtime tool checks (recommended):"
for cmd in "${warning_cmds[@]}"; do
  state="$(check_cmd "$cmd")"
  printf '  - %-14s %s\n' "$cmd" "$state"
done

echo
if [[ ${#packages[@]} -gt 0 ]]; then
  echo "Build package checks ($DISTRO_FAMILY):"
  for pkg in "${packages[@]}"; do
    if [[ " ${installed_packages[*]} " == *" $pkg "* ]]; then
      printf '  - %-28s installed\n' "$pkg"
    else
      printf '  - %-28s missing\n' "$pkg"
    fi
  done
  echo
else
  echo "Build package checks: skipped (no package list for this distro)."
  echo "  Install the Qt6, KF6 (KWallet, I18n, Notifications, CoreAddons) and libplasma"
  echo "  development packages; CMake will report anything still missing."
  echo
fi

echo "SQLite driver: $([[ "$sqlite_driver_ok" == true ]] && echo "ok" || echo "warning: not found")"

installed_missing=false
if [[ "$AUTO_INSTALL" == true ]] && [[ ${#missing_packages[@]} -gt 0 ]]; then
  echo
  echo "Installing missing dependencies..."
  "${install_cmd[@]}" "${missing_packages[@]}"
  installed_missing=true
  echo "Dependency install finished."
elif [[ "$AUTO_INSTALL" == true ]] && [[ ${#packages[@]} -eq 0 ]]; then
  echo
  echo "Note: --install-missing is only supported on Fedora and Arch; nothing was installed."
fi

echo
has_blocking=false
if [[ ${#missing_required[@]} -gt 0 ]]; then
  has_blocking=true
  echo "Blocking issues:"
  for item in "${missing_required[@]}"; do
    echo "  - Missing required command: $item"
  done
fi

if [[ ${#missing_packages[@]} -gt 0 ]] && [[ "$installed_missing" != true ]]; then
  [[ "$has_blocking" == true ]] || echo "Blocking issues:"
  has_blocking=true
  echo "  - Missing build packages. Install with:"
  echo "    ${install_cmd[*]} ${missing_packages[*]}"
fi

if [[ "$sqlite_driver_ok" != true ]]; then
  echo "Warning: Qt SQLite driver not detected. History charts may not work until Qt SQL driver is available."
fi

if [[ ${#missing_warning[@]} -gt 0 ]]; then
  echo "Warnings:"
  for item in "${missing_warning[@]}"; do
    echo "  - Missing runtime command: $item"
  done
fi

if [[ "$has_blocking" == true ]]; then
  echo
  echo "Doctor result: FAIL"
  exit 1
fi

if [[ "$STRICT" == true ]] && [[ ${#missing_warning[@]} -gt 0 ]]; then
  echo
  echo "Doctor result: FAIL (strict mode)"
  exit 1
fi

echo "Doctor result: PASS"
