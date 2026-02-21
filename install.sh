#!/bin/bash
# install.sh - Build and install the AI Usage Monitor plasmoid
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"

echo "=== AI Usage Monitor - Build & Install ==="
echo ""

# Check for required build dependencies
check_dep() {
    if ! rpm -q "$1" &>/dev/null; then
        echo "Missing dependency: $1"
        MISSING_DEPS+=("$1")
    fi
}

MISSING_DEPS=()
check_dep cmake
check_dep extra-cmake-modules
check_dep gcc-c++
check_dep qt6-qtbase-devel
check_dep qt6-qtdeclarative-devel
check_dep libplasma-devel
check_dep kf6-kwallet-devel
check_dep kf6-ki18n-devel
check_dep kf6-knotifications-devel

# Qt6 SQL / SQLite driver (bundled in qt6-qtbase on Fedora)
# Verify the driver file exists rather than checking a non-existent package
if [ ! -f /usr/lib64/qt6/plugins/sqldrivers/libqsqlite.so ] && \
   [ ! -f /usr/lib/qt6/plugins/sqldrivers/libqsqlite.so ]; then
    echo "Warning: Qt6 SQLite driver not found. Usage history may not work."
    echo "  It is normally provided by the qt6-qtbase package."
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo ""
    echo "Installing missing dependencies..."
    sudo dnf install -y "${MISSING_DEPS[@]}"
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
