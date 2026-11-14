#!/bin/bash
#
# Packages AltDeck.app as a Universal (arm64 + x86_64) signed .dmg + .zip
# and optionally notarizes + staples them with Apple notarytool.
#
# Usage:
#   ./scripts/package-release.sh [--notarize]
#
# Optional one-time notarization setup:
#   xcrun notarytool store-credentials "AltDeck-Notary" \
#     --apple-id "<your-apple-id>" --team-id "G8C56JYBN5" --password "<app-specific-password>"

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_APP="$ROOT/dist/AltDeck.app"
NOTARY_PROFILE="${NOTARY_PROFILE:-AltDeck-Notary}"
DO_NOTARIZE=0
if [[ "${1:-}" == "--notarize" ]]; then
  DO_NOTARIZE=1
fi

echo "==> Building Universal Release (arm64 + x86_64) signed with Developer ID…"
UNIVERSAL=1 "$ROOT/build-app.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST_APP/Contents/Info.plist" 2>/dev/null || echo "1.0.0")"
ZIP_OUT="$ROOT/dist/AltDeck-v${VERSION}-macOS.zip"
DMG_OUT="$ROOT/dist/AltDeck-v${VERSION}-macOS.dmg"

# Stage cleanly outside Desktop/iCloud so Finder/FileProvider cannot attach FinderInfo xattrs mid-packaging.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/altdeck-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
CLEAN_APP="$WORK_DIR/AltDeck.app"
ditto "$DIST_APP" "$CLEAN_APP"
xattr -cr "$CLEAN_APP"

CS_INFO="$(codesign -dvv "$CLEAN_APP" 2>&1)"
if ! printf '%s\n' "$CS_INFO" | grep -q "Authority=Developer ID Application:"; then
  echo "error: App is not signed with a Developer ID Application certificate." >&2
  exit 1
fi
SIGN_IDENTITY="$(printf '%s\n' "$CS_INFO" | awk -F= '/^Authority=Developer ID Application:/{print $2; exit}')"

echo "==> Verifying Hardened Runtime & strict code signature…"
codesign --verify --deep --strict -vvv "$CLEAN_APP"
codesign -d --entitlements - "$CLEAN_APP"

echo "==> Creating DMG image ($DMG_OUT)…"
DMG_STAGE="$WORK_DIR/dmg-root"
mkdir -p "$DMG_STAGE"
ditto "$CLEAN_APP" "$DMG_STAGE/AltDeck.app"
xattr -cr "$DMG_STAGE/AltDeck.app"
ln -s /Applications "$DMG_STAGE/Applications"

TMP_DMG="$WORK_DIR/AltDeck-v${VERSION}-macOS.dmg"
hdiutil create -volname "AltDeck" -srcfolder "$DMG_STAGE" -ov -format UDZO "$TMP_DMG" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$TMP_DMG"

if [[ "$DO_NOTARIZE" == "1" ]]; then
  echo "==> Submitting standalone App bundle to Apple Notary Service (profile: $NOTARY_PROFILE)…"
  TMP_APP_ZIP="$WORK_DIR/AltDeck-app-submit.zip"
  ditto -c -k --sequesterRsrc --keepParent "$CLEAN_APP" "$TMP_APP_ZIP"
  xcrun notarytool submit "$TMP_APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$CLEAN_APP"

  echo "==> Rebuilding & notarizing DMG with stapled App (profile: $NOTARY_PROFILE)…"
  rm -rf "$DMG_STAGE/AltDeck.app"
  ditto "$CLEAN_APP" "$DMG_STAGE/AltDeck.app"
  xattr -cr "$DMG_STAGE/AltDeck.app"
  codesign --verify --deep --strict -vvv "$DMG_STAGE/AltDeck.app"
  hdiutil create -volname "AltDeck" -srcfolder "$DMG_STAGE" -ov -format UDZO "$TMP_DMG" >/dev/null
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$TMP_DMG"
  xcrun notarytool submit "$TMP_DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$TMP_DMG"

  echo "==> Verifying Gatekeeper acceptance…"
  spctl --assess --type exec --verbose=4 "$CLEAN_APP"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$TMP_DMG"
fi

echo "==> Writing release artifacts to dist/…"
rm -f "$DMG_OUT" "$ZIP_OUT"
cp "$TMP_DMG" "$DMG_OUT"
ditto -c -k --sequesterRsrc --keepParent "$CLEAN_APP" "$ZIP_OUT"

echo
echo "Release artifacts ready:"
echo "  App: $DIST_APP"
echo "  DMG: $DMG_OUT"
echo "  ZIP: $ZIP_OUT"
