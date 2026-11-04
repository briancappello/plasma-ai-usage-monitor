# Justfile — Plasma AI Usage Monitor
# Usage: just <recipe>  (requires https://github.com/casey/just)
# Install: cargo install just  OR  sudo dnf install just  OR  sudo pacman -S just

# List all available recipes
default:
    @just --list

# ── Build & Test ──────────────────────────────────────────────────────────────

# Configure and build (Release mode)
build:
    bash scripts/clear_stale_cmake_cache.sh build
    cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
    cmake --build build --parallel $(nproc)

# Configure and build (Debug mode, enables unit tests)
build-debug:
    bash scripts/clear_stale_cmake_cache.sh build
    cmake -S . -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
    cmake --build build --parallel $(nproc)

# Run unit tests
test: build-debug
    ctest --test-dir build --output-on-failure

# Check version consistency across all 4 version files
check:
    bash scripts/check_version_consistency.sh
    bash scripts/check_no_hardcoded_versions.sh

# Validate install prerequisites (dependencies + runtime commands)
doctor:
    bash scripts/install_doctor.sh

# Validate and install missing dependencies automatically (Fedora/Arch)
doctor-fix:
    bash scripts/install_doctor.sh --install-missing

# Show installed versions: repo vs user-local vs system
versions:
    bash scripts/show_installed_versions.sh

# Clean the build directory
clean:
    rm -rf build

# ── System-Wide Install (requires sudo) ───────────────────────────────────────

# Build, install to /usr (sudo), and remove any shadowing user-local copy
install: build
    sudo cmake --install build
    bash scripts/remove_user_local_plasmoid.sh

# Reinstall: uninstall then install
reinstall: uninstall install

# Uninstall system-wide install using CMake's install manifest
uninstall:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -f build/install_manifest.txt ]; then
        sudo xargs rm -f < build/install_manifest.txt
        sudo ldconfig
        echo "Uninstalled. Removed files listed in build/install_manifest.txt"
    else
        echo "No build/install_manifest.txt found."
        echo "Run 'just install' first so CMake records what it installs."
        exit 1
    fi

# Guided interactive uninstall: detects and removes user-local and/or system installs
uninstall-guided:
    bash uninstall.sh

# Restart plasmashell to pick up changes
reload:
    bash scripts/reload_plasma.sh

# One-step dev iteration: rebuild, install to /usr, restart plasmashell
dev: install reload

# Guided source build/install (doctor checks, confirm, build, install to /usr)
bootstrap:
    bash scripts/install_bootstrap.sh

# Guided source build/install with dependency auto-fix on Fedora/Arch
bootstrap-source:
    bash scripts/install_bootstrap.sh --install-missing

# ── Version Management ────────────────────────────────────────────────────────

# Bump version across all 4 files: just bump VERSION=3.3.0
bump VERSION:
    bash scripts/bump_version.sh {{VERSION}}
