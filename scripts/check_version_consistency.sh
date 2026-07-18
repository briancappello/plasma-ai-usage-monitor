#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

cmake_version="$(sed -n 's/^project(plasma-ai-usage-monitor VERSION \([0-9.]*\)).*/\1/p' CMakeLists.txt | head -1)"
metadata_version="$(sed -n 's/.*"Version": "\([0-9.]*\)".*/\1/p' package/metadata.json | head -1)"
spec_version="$(sed -n 's/^Version:[[:space:]]*\([0-9.]*\).*/\1/p' plasma-ai-usage-monitor.spec | head -1)"
metainfo_version="$(sed -n 's/.*<release version="\([0-9.]*\)".*/\1/p' com.github.loofi.aiusagemonitor.metainfo.xml | head -1)"
semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'

if [[ -z "$cmake_version" || -z "$metadata_version" || -z "$spec_version" ]]; then
  echo "Failed to parse one or more version values"
  echo "  CMake:    '${cmake_version}'"
  echo "  metadata: '${metadata_version}'"
  echo "  spec:     '${spec_version}'"
  exit 1
fi

if [[ "$cmake_version" != "$metadata_version" || "$cmake_version" != "$spec_version" ]]; then
  echo "Version mismatch detected"
  echo "  CMake:    ${cmake_version}"
  echo "  metadata: ${metadata_version}"
  echo "  spec:     ${spec_version}"
  exit 1
fi

if [[ -n "$metainfo_version" && "$metainfo_version" != "$cmake_version" ]]; then
  echo "AppStream metainfo version mismatch"
  echo "  CMake:    ${cmake_version}"
  echo "  metainfo: ${metainfo_version}"
  exit 1
fi

if [[ ! "$cmake_version" =~ $semver_re || ! "$metadata_version" =~ $semver_re || ! "$spec_version" =~ $semver_re ]]; then
  echo "Invalid version format detected (expected MAJOR.MINOR.PATCH)"
  echo "  CMake:    ${cmake_version}"
  echo "  metadata: ${metadata_version}"
  echo "  spec:     ${spec_version}"
  exit 1
fi

echo "Version consistency OK: ${cmake_version}"

user_metadata="${HOME}/.local/share/plasma/plasmoids/com.github.loofi.aiusagemonitor/metadata.json"
system_metadata="/usr/share/plasma/plasmoids/com.github.loofi.aiusagemonitor/metadata.json"

extract_installed_version() {
  local file="$1"
  [[ -f "$file" ]] || return 0
  sed -n 's/.*"Version": "\([0-9.]*\)".*/\1/p' "$file" | head -1
}

user_version="$(extract_installed_version "$user_metadata")"
system_version="$(extract_installed_version "$system_metadata")"

if [[ -n "${user_version}" && "${user_version}" != "${cmake_version}" ]]; then
  echo "Warning: local user plasmoid version (${user_version}) differs from repo (${cmake_version})"
fi

if [[ -n "${system_version}" && "${system_version}" != "${cmake_version}" ]]; then
  echo "Warning: system plasmoid version (${system_version}) differs from repo (${cmake_version})"
fi
