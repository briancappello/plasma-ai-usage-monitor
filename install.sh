#!/bin/bash
# install.sh - Build and install the AI Usage Monitor plasmoid
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

echo "=== AI Usage Monitor - Build & Install ==="
echo ""

# Detect distro
if [ -f /etc/os-release ]; then
    . /etc/os-release
    DISTRO_ID="${ID:-unknown}"
else
    DISTRO_ID="unknown"
fi

case "$DISTRO_ID" in
    fedora)
        DEPS=(cmake extra-cmake-modules gcc-c++ qt6-qtbase-devel
              qt6-qtdeclarative-devel libplasma-devel kf6-kwallet-devel
              kf6-ki18n-devel kf6-knotifications-devel)
        check_dep() {
            if ! rpm -q "$1" &>/dev/null; then
                echo "Missing dependency: $1"
                MISSING_DEPS+=("$1")
            fi
        }
        install_deps() { sudo dnf install -y "${MISSING_DEPS[@]}"; }
        ;;
    arch)
        DEPS=(cmake extra-cmake-modules gcc qt6-base qt6-declarative
              plasma-desktop kwallet ki18n knotifications)
        check_dep() {
            if ! pacman -Qi "$1" &>/dev/null; then
                echo "Missing dependency: $1"
                MISSING_DEPS+=("$1")
            fi
        }
        install_deps() { sudo pacman -S --needed --noconfirm "${MISSING_DEPS[@]}"; }
        ;;
    *)
        echo "Warning: Unsupported distro '$DISTRO_ID'. Skipping dependency check."
        echo "  Please manually install: cmake, extra-cmake-modules, Qt6, KF6 (kwallet, ki18n, knotifications), libplasma"
        DEPS=()
        check_dep() { :; }
        install_deps() { :; }
        ;;
esac

MISSING_DEPS=()
for dep in "${DEPS[@]}"; do
    check_dep "$dep"
done

# Qt6 SQL / SQLite driver
# On Fedora this is bundled in qt6-qtbase; on Arch it is in qt6-base
if [ ! -f /usr/lib64/qt6/plugins/sqldrivers/libqsqlite.so ] && \
   [ ! -f /usr/lib/qt6/plugins/sqldrivers/libqsqlite.so ]; then
    echo "Warning: Qt6 SQLite driver not found. Usage history may not work."
    case "$DISTRO_ID" in
        fedora) echo "  It is normally provided by the qt6-qtbase package." ;;
        arch)   echo "  It is normally provided by the qt6-base package." ;;
        *)      echo "  Ensure your Qt6 base package includes SQLite support." ;;
    esac
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo ""
    echo "Installing missing dependencies..."
    install_deps
    echo ""
fi

# Build
echo "Building..."
mkdir -p "$BUILD_DIR"
cmake -S "$PROJECT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_BUILD_TYPE=Release

cmake --build "$BUILD_DIR" --parallel "$(nproc)"

# Clear Cache
rm -rf ~/.cache/plasma* ~/.cache/qmlcache

# Install
echo ""
echo "Installing (requires sudo)..."
sudo cmake --install "$BUILD_DIR"

echo ""
echo "=== Installation complete! ==="
echo ""
echo "To use the widget:"
echo "  1. Right-click your desktop or panel"
echo "  2. Select 'Add Widgets...'"
echo "  3. Search for 'AI Usage Monitor'"
echo "  4. Drag it to your panel or desktop"
echo "  5. Right-click the widget > Configure to add API keys"
echo ""
echo "To test without installing to panel:"
echo "  plasmawindowed com.github.loofi.aiusagemonitor"
echo ""
echo "To restart Plasma Shell (if widget doesn't appear):"
echo "  plasmashell --replace &"
echo ""
