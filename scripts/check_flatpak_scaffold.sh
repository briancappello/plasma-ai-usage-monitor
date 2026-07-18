#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

MANIFEST="packaging/flatpak/com.github.loofi.aiusagemonitor.yaml"
README="packaging/flatpak/README.md"
METADATA="package/metadata.json"
CMAKE_FILE="CMakeLists.txt"

[[ -f "$MANIFEST" ]] || { echo "Missing ${MANIFEST}" >&2; exit 1; }
[[ -f "$README" ]] || { echo "Missing ${README}" >&2; exit 1; }
[[ -f "$METADATA" ]] || { echo "Missing ${METADATA}" >&2; exit 1; }
[[ -f "$CMAKE_FILE" ]] || { echo "Missing ${CMAKE_FILE}" >&2; exit 1; }

manifest_app_id="$(sed -n 's/^app-id:[[:space:]]*\(.*\)$/\1/p' "$MANIFEST" | head -1 | tr -d "'\"\r")"
manifest_runtime="$(sed -n 's/^runtime:[[:space:]]*\(.*\)$/\1/p' "$MANIFEST" | head -1 | tr -d "'\"\r")"
manifest_runtime_version="$(sed -n 's/^runtime-version:[[:space:]]*\(.*\)$/\1/p' "$MANIFEST" | head -1 | tr -d "'\"\r")"
manifest_command="$(sed -n 's/^command:[[:space:]]*\(.*\)$/\1/p' "$MANIFEST" | head -1 | tr -d "'\"\r")"

metadata_id="$(sed -n 's/.*"Id":[[:space:]]*"\([^"]*\)".*/\1/p' "$METADATA" | head -1)"
metadata_version="$(sed -n 's/.*"Version":[[:space:]]*"\([^"]*\)".*/\1/p' "$METADATA" | head -1)"
cmake_version="$(sed -n 's/^project(plasma-ai-usage-monitor VERSION \([0-9.]*\)).*/\1/p' "$CMAKE_FILE" | head -1)"

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'

[[ "$manifest_app_id" == "com.github.loofi.aiusagemonitor" ]] || {
  echo "Flatpak manifest app-id mismatch" >&2
  exit 1
}

[[ "$manifest_runtime" == "org.kde.Platform" ]] || {
  echo "Flatpak manifest runtime missing/invalid" >&2
  exit 1
}

[[ -n "$manifest_runtime_version" ]] || {
  echo "Flatpak manifest runtime-version missing" >&2
  exit 1
}

[[ "$manifest_command" == "plasmawindowed" ]] || {
  echo "Flatpak manifest command should be plasmawindowed" >&2
  exit 1
}

[[ "$metadata_id" == "$manifest_app_id" ]] || {
  echo "Flatpak/metadata app ID mismatch" >&2
  echo "  manifest: ${manifest_app_id}" >&2
  echo "  metadata: ${metadata_id}" >&2
  exit 1
}

[[ -n "$metadata_version" && -n "$cmake_version" ]] || {
  echo "Failed to parse metadata/CMake versions" >&2
  exit 1
}

[[ "$metadata_version" == "$cmake_version" ]] || {
  echo "Version mismatch between metadata and CMake" >&2
  echo "  metadata: ${metadata_version}" >&2
  echo "  CMake:    ${cmake_version}" >&2
  exit 1
}

[[ "$metadata_version" =~ $semver_re ]] || {
  echo "Metadata version is not semantic (MAJOR.MINOR.PATCH): ${metadata_version}" >&2
  exit 1
}

echo "Flatpak scaffold check OK (app-id=${manifest_app_id}, runtime=${manifest_runtime}/${manifest_runtime_version}, version=${metadata_version})"
