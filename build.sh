#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"
source scripts/config.sh
if [[ "${NIMBO_RELEASE_BUILD:-0}" == 1 ]]; then
  source scripts/release-mode.sh
  configure_release_signing
fi
bash scripts/fetch-sparkle.sh

APP_NAME="Nimbo"
APP_DIR="build/${APP_NAME}.app"
LEGACY_APP_DIR="build/MacCleaner.app"
MACOS_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"
BIN="${MACOS_DIR}/${APP_NAME}"

rm -rf "${APP_DIR}" "${LEGACY_APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RES_DIR}" "build/ModuleCache"

ARCH="$(uname -m)"
ARCHITECTURES="${NIMBO_ARCHS:-$ARCH}"
SDK_PATH="$(xcrun --show-sdk-path)"

BINARIES=()
for ARCH in $ARCHITECTURES; do
[[ "$ARCH" == arm64 || "$ARCH" == x86_64 ]] || { echo "Nepodporovaná architektura: $ARCH" >&2; exit 1; }
echo "▸ Kompiluji Nimbo (${ARCH})…"
xcrun swiftc \
  -parse-as-library \
  -swift-version 5 \
  -O \
  -module-cache-path "build/ModuleCache" \
  -sdk "${SDK_PATH}" \
  -framework SwiftUI -framework AppKit -framework WebKit \
  -F "$SPARKLE_DIR" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -target "${ARCH}-apple-macos14.0" \
  -o "build/Nimbo-${ARCH}" \
  Sources/*.swift
BINARIES+=("build/Nimbo-${ARCH}")
done
xcrun lipo -create "${BINARIES[@]}" -output "$BIN"
mkdir -p "$APP_DIR/Contents/Frameworks"
ditto "$SPARKLE_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE_DIR/LICENSE" "$RES_DIR/Sparkle-LICENSE.txt"

cp Assets/nimbo-logo-dark-transparent.png "${RES_DIR}/nimbo-logo-dark.png"
cp Assets/nimbo-logo-light-transparent.png "${RES_DIR}/nimbo-logo-light.png"
cp Assets/nimbo-icon-dark-transparent.png "${RES_DIR}/nimbo-icon-dark.png"
cp Assets/nimbo-icon-light-transparent.png "${RES_DIR}/nimbo-icon-light.png"
cp Assets/nimbo-landscape-header.png "${RES_DIR}/nimbo-landscape-header.png"

plutil -create xml1 "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundleName -string "${APP_NAME}" "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "${APP_NAME}" "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "local.nimbo.app" "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "${APP_NAME}" "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundlePackageType -string "APPL" "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$APP_BUILD" "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "${APP_DIR}/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "14.0" "${APP_DIR}/Contents/Info.plist"
plutil -insert LSApplicationCategoryType -string "public.app-category.utilities" "${APP_DIR}/Contents/Info.plist"
plutil -insert NSHighResolutionCapable -bool YES "${APP_DIR}/Contents/Info.plist"
plutil -insert NSAppleEventsUsageDescription -string "Nimbo používá System Events k zobrazení a změně aplikací spouštěných po přihlášení." "${APP_DIR}/Contents/Info.plist"
plutil -insert CFBundleIconFile -string "nimbo-icon-dark.png" "${APP_DIR}/Contents/Info.plist"

if [[ -n "$UPDATE_FEED_URL" ]]; then
  plutil -insert SUFeedURL -string "$UPDATE_FEED_URL" "$APP_DIR/Contents/Info.plist"
  plutil -insert SUPublicEDKey -string "$SPARKLE_PUBLIC_ED_KEY" "$APP_DIR/Contents/Info.plist"
  plutil -insert SUVerifyUpdateBeforeExtraction -bool YES "$APP_DIR/Contents/Info.plist"
  plutil -insert SURequireSignedFeed -bool YES "$APP_DIR/Contents/Info.plist"
fi
# Opt-in checks; installation always requires user interaction.
plutil -insert SUEnableAutomaticChecks -bool NO "$APP_DIR/Contents/Info.plist"
plutil -insert SUAllowsAutomaticUpdates -bool NO "$APP_DIR/Contents/Info.plist"
plutil -insert SUSendProfileInfo -bool NO "$APP_DIR/Contents/Info.plist"
plutil -insert SUScheduledCheckInterval -integer 86400 "$APP_DIR/Contents/Info.plist"
bash scripts/sign-app.sh "$APP_DIR"
echo "✓ Hotovo: ${APP_DIR}"
echo "  Spustit: open \"${APP_DIR}\""
