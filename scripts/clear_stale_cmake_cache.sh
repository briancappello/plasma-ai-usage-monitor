#!/usr/bin/env bash
# CMake refuses to reuse a build dir whose cache was generated for another
# source path (e.g. after the checkout was moved). Drop just the cache so the
# next configure starts fresh; install_manifest.txt is kept for uninstall.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${1:-$ROOT_DIR/build}"
CACHE="$BUILD_DIR/CMakeCache.txt"

[[ -f "$CACHE" ]] || exit 0

cached_source="$(sed -n 's/^CMAKE_HOME_DIRECTORY:INTERNAL=//p' "$CACHE")"
if [[ -z "$cached_source" ]] || [[ "$(realpath -m "$cached_source")" == "$(realpath -m "$ROOT_DIR")" ]]; then
  exit 0
fi

echo "Build dir was configured for $cached_source; clearing stale CMake cache."
rm -rf "$CACHE" "$BUILD_DIR/CMakeFiles"
