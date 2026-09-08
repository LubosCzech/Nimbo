#!/bin/bash
# Prepare a verified local release, upload a draft, then explicitly publish it.
set -euo pipefail
cd "$(dirname "$0")/.."
usage() {
  echo "Použití: bash scripts/release.sh prepare [--first-release] | upload | publish"
  echo "prepare: universal build, Developer ID, notarizace, DMG a podepsaný appcast"
  echo "upload: nahraje ověřené soubory do nového GitHub draftu (vyžaduje existující tag)"
  echo "publish: ověří draft a zveřejní jej jako Latest"
}
[[ "${1:-}" != --help && "${1:-}" != -h ]] || { usage; exit 0; }
ACTION="${1:-}"
[[ "$ACTION" == prepare || "$ACTION" == upload || "$ACTION" == publish ]] || { usage; exit 1; }
shift
FIRST=false
if [[ "$ACTION" == prepare && "${1:-}" == --first-release ]]; then FIRST=true; shift; fi
[[ $# == 0 ]] || { usage; exit 1; }
source scripts/config.sh
[[ -n "$UPDATE_FEED_URL" ]] || { echo "Nejprve nastavte repozitář a veřejný EdDSA klíč v release.env." >&2; exit 1; }
command -v gh >/dev/null || { echo "Nainstalujte GitHub CLI (gh) a spusťte gh auth login." >&2; exit 1; }
[[ "$(gh api "repos/$GITHUB_REPOSITORY" --jq .private)" == false ]] || { echo "Aktualizace vyžadují veřejný repozitář." >&2; exit 1; }
bash scripts/fetch-sparkle.sh
PUBLIC_KEY="$("$SPARKLE_DIR/bin/generate_keys" --account "$SPARKLE_KEY_ACCOUNT" -p)"
[[ "$PUBLIC_KEY" == "$SPARKLE_PUBLIC_ED_KEY" ]] || { echo "Podpisový klíč v Klíčence nesouhlasí s release.env." >&2; exit 1; }
TAG="v$APP_VERSION"
OUTPUT="$PWD/dist/releases/$TAG"
DMG_NAME="Nimbo-$APP_VERSION-universal.dmg"
PREFIX="https://github.com/$GITHUB_REPOSITORY/releases/download/$TAG/"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/nimbo-release.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

check_previous() {
  if "$FIRST"; then
    [[ "$(gh release list --repo "$GITHUB_REPOSITORY" --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq length)" == 0 ]] || {
      echo "Repozitář již má stabilní vydání; nepoužívejte --first-release." >&2; exit 1;
    }
  else
    curl --fail --location --proto '=https' --tlsv1.2 "$UPDATE_FEED_URL" -o "$WORK/previous.xml"
    "$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$WORK/previous.xml"
    # All Nimbo Sparkle builds use positive integer build numbers.
    local previous
    previous="$(xmllint --xpath 'string(/rss/channel/item[1]/*[local-name()="version"])' "$WORK/previous.xml")"
    [[ "$previous" =~ ^[1-9][0-9]*$ && "$APP_BUILD" -gt "$previous" ]] || {
      echo "APP_BUILD musí být vyšší než aktuální vydání ($previous)." >&2; exit 1;
    }
  fi
}

verify_local() {
  [[ -f "$OUTPUT/.ready" ]] || { echo "Nejprve spusťte prepare." >&2; exit 1; }
  (cd "$OUTPUT" && shasum -a 256 -c SHA256SUMS)
  "$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$OUTPUT/appcast.xml"
  local signature
  signature="$(python3 scripts/validate-appcast.py "$OUTPUT/appcast.xml" "$OUTPUT/$DMG_NAME" "$APP_BUILD" "$APP_VERSION" "$PREFIX")"
  "$SPARKLE_DIR/bin/sign_update" --account "$SPARKLE_KEY_ACCOUNT" --verify "$OUTPUT/$DMG_NAME" "$signature"
  xcrun stapler validate "$OUTPUT/$DMG_NAME"
  codesign --verify --strict "$OUTPUT/$DMG_NAME"
}

case "$ACTION" in
prepare)
  [[ "${NIMBO_SIGN_IDENTITY:-}" == 'Developer ID Application:'* ]] || { echo "Nastavte NIMBO_SIGN_IDENTITY na Developer ID Application certifikát." >&2; exit 1; }
  [[ -n "${NIMBO_NOTARY_PROFILE:-}" ]] || { echo "Nastavte NIMBO_NOTARY_PROFILE (profil notarytool v Klíčence)." >&2; exit 1; }
  [[ -s RELEASE_NOTES.md ]] || { echo "Vyplňte RELEASE_NOTES.md." >&2; exit 1; }
  [[ ! -e "$OUTPUT" ]] || { echo "$OUTPUT již existuje. Použijte novou verzi nebo neúplný výstup přesuňte." >&2; exit 1; }
  check_previous
  # Verify the tag exists remotely. It must identify the reviewed source revision.
  gh api "repos/$GITHUB_REPOSITORY/git/ref/tags/$TAG" >/dev/null
  mkdir -p "$OUTPUT"
  export NIMBO_SIGN_IDENTITY
  NIMBO_ARCHS="arm64 x86_64" bash build.sh
  ditto -c -k --keepParent build/Nimbo.app "$WORK/notarize.zip"
  xcrun notarytool submit "$WORK/notarize.zip" --keychain-profile "$NIMBO_NOTARY_PROFILE" --wait
  xcrun stapler staple build/Nimbo.app
  xcrun stapler validate build/Nimbo.app
  spctl --assess --type execute --verbose=2 build/Nimbo.app
  NIMBO_DMG_DIR="$OUTPUT" bash create-dmg.sh --no-build
  codesign --force --sign "$NIMBO_SIGN_IDENTITY" --timestamp "$OUTPUT/$DMG_NAME"
  xcrun notarytool submit "$OUTPUT/$DMG_NAME" --keychain-profile "$NIMBO_NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUTPUT/$DMG_NAME"
  hdiutil verify "$OUTPUT/$DMG_NAME"
  cp RELEASE_NOTES.md "$OUTPUT/${DMG_NAME%.dmg}.md"
  cp RELEASE_NOTES.md "$OUTPUT/RELEASE_NOTES.md"
  # Preserve earlier signed entries (their download URLs continue pointing to old releases).
  if [[ -f "$WORK/previous.xml" ]]; then cp "$WORK/previous.xml" "$OUTPUT/appcast.xml"; fi
  "$SPARKLE_DIR/bin/generate_appcast" --account "$SPARKLE_KEY_ACCOUNT" \
    --download-url-prefix "$PREFIX" --embed-release-notes --maximum-deltas 0 \
    -o "$OUTPUT/appcast.xml" "$OUTPUT"
  (cd "$OUTPUT" && shasum -a 256 "$DMG_NAME" appcast.xml RELEASE_NOTES.md > SHA256SUMS)
  touch "$OUTPUT/.ready"
  verify_local
  echo "✓ Připraveno: $OUTPUT. Další krok: bash scripts/release.sh upload"
  ;;
upload)
  verify_local
  gh release create "$TAG" --repo "$GITHUB_REPOSITORY" --verify-tag --draft \
    --title "Nimbo $APP_VERSION" --notes-file "$OUTPUT/RELEASE_NOTES.md" \
    "$OUTPUT/$DMG_NAME" "$OUTPUT/appcast.xml" "$OUTPUT/SHA256SUMS" "$OUTPUT/RELEASE_NOTES.md"
  echo "✓ Draft nahrán. Po kontrole: bash scripts/release.sh publish"
  ;;
publish)
  verify_local
  [[ "$(gh release view "$TAG" --repo "$GITHUB_REPOSITORY" --json isDraft --jq .isDraft)" == true ]] || { echo "Očekáván nepublikovaný draft." >&2; exit 1; }
  gh release download "$TAG" --repo "$GITHUB_REPOSITORY" --dir "$WORK/download" \
    --pattern "$DMG_NAME" --pattern appcast.xml --pattern SHA256SUMS --pattern RELEASE_NOTES.md
  for file in "$DMG_NAME" appcast.xml SHA256SUMS RELEASE_NOTES.md; do
    cmp "$OUTPUT/$file" "$WORK/download/$file"
  done
  # A first release has no previous appcast; otherwise reject publishing an older build.
  if [[ "$(gh release list --repo "$GITHUB_REPOSITORY" --exclude-drafts --exclude-pre-releases --limit 1 --json tagName --jq length)" != 0 ]]; then check_previous; fi
  gh release edit "$TAG" --repo "$GITHUB_REPOSITORY" --draft=false --prerelease=false --latest
  curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$UPDATE_FEED_URL" -o "$WORK/published.xml"
  cmp "$OUTPUT/appcast.xml" "$WORK/published.xml"
  echo "✓ Zveřejněno a ověřeno: https://github.com/$GITHUB_REPOSITORY/releases/tag/$TAG"
  ;;
esac
