#!/bin/bash
# Every regression suite in one run. No suite touches user files, sends an
# Apple Event, signs anything or reaches Apple: see the per-suite PASS lines.
# Plain strings, not arrays: macOS ships bash 3.2, where an empty array under
# `set -u` aborts — which would break exactly the failure report we need.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/ModuleCache

FAILED=""
swift_suite() {
  local name="$1"; shift
  printf '▸ %s\n' "$name"
  xcrun swiftc -module-cache-path build/ModuleCache "$@" -o "build/$name" && "build/$name" \
    || FAILED="$FAILED $name"
  return 0
}
shell_suite() {
  local name="$1"; shift
  printf '▸ %s\n' "$name"
  "$@" || FAILED="$FAILED $name"
  return 0
}

swift_suite removal-diagnostics-tests \
  Sources/Models.swift Sources/RemovalDiagnostics.swift Sources/FileScanner.swift \
  Tests/RemovalDiagnosticsTests.swift
swift_suite uninstall-tests \
  Sources/Models.swift Sources/RemovalDiagnostics.swift Sources/FinderTrashService.swift \
  Sources/UninstallService.swift Tests/UninstallTests.swift
swift_suite finder-trash-tests \
  Sources/Models.swift Sources/RemovalDiagnostics.swift Sources/FinderTrashService.swift \
  Sources/UninstallService.swift Tests/FinderTrashTests.swift
swift_suite preferences-migration-tests \
  Sources/StartupService.swift Sources/PreferencesMigration.swift Tests/PreferencesMigrationTests.swift
swift_suite permission-tests \
  Sources/PermissionChecks.swift Sources/PermissionController.swift Tests/PermissionTests.swift
swift_suite startup-tests Sources/StartupService.swift Tests/StartupTests.swift
# Verifies SF Symbols exist on THIS macOS runtime, so it belongs to a release.
swift_suite design-tests Sources/Models.swift Tests/DesignTests.swift

shell_suite appcast-tests python3 -m unittest discover -s Tests -p 'test_*.py'
shell_suite release-mode-tests bash Tests/release-mode-tests.sh

if [[ -n "$FAILED" ]]; then
  printf '\n✗ Selhalo:%s\n' "$FAILED" >&2
  exit 1
fi
printf '\n✓ Všechny sady prošly.\n'
