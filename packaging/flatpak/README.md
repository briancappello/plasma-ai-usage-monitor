# Flatpak Scaffold (Validation Baseline)

This directory contains the canonical Flatpak manifest for distribution work.

Current scope:

- Establish canonical manifest location: `packaging/flatpak/com.github.loofi.aiusagemonitor.yaml`
- Enforce deterministic scaffold validation in CI and release workflows
- Verify manifest identity and runtime fields against project metadata
- Keep publication out-of-scope until full runtime/plugin integration is complete

What is validated:

- Manifest exists and includes expected core fields (`app-id`, `runtime`, `runtime-version`, `command`)
- Manifest `app-id` equals plasmoid metadata `KPlugin.Id`
- `package/metadata.json` version matches `CMakeLists.txt` project version
- Packaging helper scripts pass local integrity checks

Local validation:

- `bash scripts/check_version_consistency.sh`
- `bash scripts/check_flatpak_scaffold.sh`
- `bash scripts/package_source_tarball.sh --check`
- `bash scripts/package_plasmoid.sh --check`

Future work can extend this baseline with full Flatpak builds, runtime dependency integration, and publish automation.
