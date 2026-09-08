#!/bin/bash
# Build and package Nimbo using macOS tools; no additional dependencies.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_APP=true
case "${1:-}" in
  --no-build) BUILD_APP=false; shift ;;
  --help|-h)
    echo "Použití: $0 [--no-build]"
    echo "Sestaví Nimbo a vytvoří dist/Nimbo-<verze>-<architektura>.dmg."
    echo "--no-build zabalí existující build/Nimbo.app. Existující DMG nepřepisuje."
    exit 0 ;;
esac
if [[ $# -ne 0 ]]; then
  echo "Neznámý parametr. Použijte --help." >&2
  exit 1
fi
[[ "$(uname -s)" == Darwin ]] || { echo "Skript vyžaduje macOS." >&2; exit 1; }
if "$BUILD_APP"; then /bin/bash "${PROJECT_DIR}/build.sh"; fi

APP_PATH="${PROJECT_DIR}/build/Nimbo.app"
PLIST="${APP_PATH}/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo "Chybí build/Nimbo.app. Spusťte skript bez --no-build." >&2; exit 1; }
/usr/bin/plutil -lint "$PLIST"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PLIST")"
[[ "$EXECUTABLE" == Nimbo ]] || { echo "Neočekávaná aplikace v build/Nimbo.app." >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+([.][0-9]+)*$ ]] || { echo "Neplatná verze: $VERSION" >&2; exit 1; }
ARCHS="$(/usr/bin/lipo -archs "${APP_PATH}/Contents/MacOS/Nimbo")"
ARCH_LABEL="${ARCHS// /-}"
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then ARCH_LABEL=universal; fi
/usr/bin/codesign --verify --deep --strict "$APP_PATH"

DIST_DIR="${NIMBO_DMG_DIR:-${PROJECT_DIR}/dist}"
mkdir -p "$DIST_DIR"
OUTPUT="${DIST_DIR}/Nimbo-${VERSION}-${ARCH_LABEL}.dmg"
if [[ -e "$OUTPUT" || -L "$OUTPUT" ]]; then
  echo "DMG již existuje: $OUTPUT" >&2
  echo "Před novým vytvořením ho přejmenujte nebo přesuňte." >&2
  exit 1
fi

STAGING="$(mktemp -d "${DIST_DIR}/.nimbo-dmg.XXXXXX")"
cleanup() {
  # Only remove the unique temporary directory created by this invocation.
  if [[ -n "${STAGING:-}" && "$STAGING" == "$DIST_DIR"/.nimbo-dmg.* && -d "$STAGING" ]]; then
    /bin/rm -rf "$STAGING"
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "${STAGING}/contents"
/usr/bin/ditto "$APP_PATH" "${STAGING}/contents/Nimbo.app"
/bin/ln -s /Applications "${STAGING}/contents/Applications"
/usr/bin/codesign --verify --deep --strict "${STAGING}/contents/Nimbo.app"

echo "▸ Vytvářím instalační DMG…"
/usr/bin/hdiutil create -volname Nimbo -srcfolder "${STAGING}/contents" \
  -fs HFS+ -format UDZO "${STAGING}/Nimbo.dmg"
/usr/bin/hdiutil verify "${STAGING}/Nimbo.dmg"
# Publish only a complete, verified image, without replacing earlier output.
/bin/ln "${STAGING}/Nimbo.dmg" "$OUTPUT"
echo "✓ Hotovo: $OUTPUT"
echo "Instalace: otevřete DMG a přetáhněte Nimbo do Applications."
