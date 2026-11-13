#!/bin/bash
#
# Builds TabStation.app — a real, double-clickable macOS app bundle.
#
# SwiftPM produces a bare executable, so this script wraps it in a bundle with
# an Info.plist and ad-hoc signs it. The signature matters: TCC (Screen
# Recording / Accessibility) identifies an app by its signed bundle, so an
# unsigned binary can be denied or lose its grant on every rebuild.
#
# Usage:  ./build-app.sh [debug|release]

set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="AltDeck"
BUNDLE_ID="com.tabstation.TabStation"
VERSION="1.0.0"
APP="$ROOT/dist/$APP_NAME.app"

# Keep build artefacts off the project directory. When the project lives on a
# file-synced Desktop, building in-tree makes every SDK stat-cache read a network
# round trip — the same build went from 61s to over 12 minutes.
SCRATCH="${TABSTATION_SCRATCH:-$HOME/.cache/tabstation-build}"
mkdir -p "$SCRATCH"
ICONSET="$SCRATCH/AppIcon.iconset"

# DEVELOPER_DIR sometimes points at an Xcode that has since been removed
# (e.g. a deleted Xcode-beta). Fall back to whatever is actually installed.
if [[ -n "${DEVELOPER_DIR:-}" && ! -d "$DEVELOPER_DIR" ]]; then
  echo "==> DEVELOPER_DIR points at a missing install; using xcode-select's choice."
  unset DEVELOPER_DIR
fi
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

swift_build() {
  swift build --configuration "$CONFIG" --package-path "$ROOT" --scratch-path "$SCRATCH" "$@"
}

echo "==> Building ($CONFIG)…"
swift_build
BIN_PATH="$(swift_build --show-bin-path)"
BINARY="$BIN_PATH/TabStation"

if [[ ! -x "$BINARY" ]]; then
  echo "error: expected executable at $BINARY" >&2
  exit 1
fi

echo "==> Assembling bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
    <key>NSAppleEventsUsageDescription</key><string>AltDeck uses Apple Events to list and switch open browser tabs in Chrome, Safari, Arc, Edge, and Brave.</string>
</dict>
</plist>
PLIST

echo "==> Generating icon…"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
MASTER_ICON="$ROOT/Assets/AppIcon-1024.png"
if [[ -f "$MASTER_ICON" ]] && command -v sips >/dev/null 2>&1; then
  for spec in "16:icon_16x16.png" "32:icon_16x16@2x.png" "32:icon_32x32.png" "64:icon_32x32@2x.png" "128:icon_128x128.png" "256:icon_128x128@2x.png" "256:icon_256x256.png" "512:icon_256x256@2x.png" "512:icon_512x512.png" "1024:icon_512x512@2x.png"; do
    px="${spec%%:*}"
    out="${spec#*:}"
    sips -z "$px" "$px" "$MASTER_ICON" --out "$ICONSET/$out" >/dev/null 2>&1
  done
  if iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    echo "    AppIcon.icns created from Assets/AppIcon-1024.png"
  else
    echo "    iconutil failed" >&2
    rm -f "$APP/Contents/Resources/AppIcon.icns"
  fi
elif swift "$ROOT/Tools/GenerateIcon.swift" "$ICONSET" >/dev/null 2>&1 \
   && iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    AppIcon.icns created"
else
  echo "    icon generation skipped (non-fatal)"
  rm -f "$APP/Contents/Resources/AppIcon.icns"
fi
rm -rf "$ICONSET"

SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2}' | head -n1)"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  SIGN_ARG="$SIGNING_IDENTITY"
else
  SIGN_ARG="-"
fi

STAGE="$(mktemp -d "${TMPDIR:-/tmp}/tabstation-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/$APP_NAME.app"

xattr -cr "$STAGE/$APP_NAME.app"
if [[ "$SIGN_ARG" == "-" ]]; then
  if ! codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID" -r="designated => identifier \"$BUNDLE_ID\"" "$STAGE/$APP_NAME.app" >/dev/null 2>&1; then
    codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID" "$STAGE/$APP_NAME.app" >/dev/null 2>&1
  fi
else
  if ! codesign --force --sign "$SIGN_ARG" --timestamp=none --identifier "$BUNDLE_ID" "$STAGE/$APP_NAME.app" >/dev/null 2>&1; then
    echo "    error: codesign with $SIGN_ARG failed, falling back to ad-hoc" >&2
    codesign --force --sign - --timestamp=none --identifier "$BUNDLE_ID" "$STAGE/$APP_NAME.app" >/dev/null 2>&1
  fi
fi

rm -rf "$APP"
cp -R "$STAGE/$APP_NAME.app" "$APP"

# Strip whatever the copy picked up and confirm the signature still holds.
# (Signatures hash file contents and the resource seal, not xattrs, so removing
# the Finder metadata afterwards is safe.)
verified=0
for _ in 1 2 3 4 5; do
  xattr -cr "$APP" 2>/dev/null || true
  if codesign --verify --deep --strict "$APP" >/dev/null 2>&1; then
    verified=1
    break
  fi
  sleep 0.4
done

if [[ "$verified" == "1" ]]; then
  echo "    signature OK ($BUNDLE_ID, $SIGN_ARG)"
else
  echo "    warning: signature verification failed" >&2
  echo "    tip: 'cp -R \"$APP\" /Applications/' avoids file-synced folder metadata." >&2
fi

echo
echo "Built: $APP"

# If an installed copy already exists, keep it in sync automatically. A stale
# copy left lying around is genuinely confusing — it looks identical in Finder
# but silently lacks whatever was added since.
# Install to /Applications — the folder Finder's sidebar actually shows.
# ~/Applications is hidden by default, which makes an app there look "missing".
INSTALLED="${TABSTATION_INSTALL:-/Applications}/$APP_NAME.app"
LEGACY_INSTALLED="${TABSTATION_INSTALL:-/Applications}/TabStation.app"
if [[ "${1:-}" == "--install" || -d "$INSTALLED" || -d "$LEGACY_INSTALLED" ]]; then
  WAS_RUNNING=0
  if pgrep -fx "$INSTALLED/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    WAS_RUNNING=1
    pkill -fx "$INSTALLED/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || true
    sleep 0.3
  fi
  if pgrep -fx "$LEGACY_INSTALLED/Contents/MacOS/TabStation" >/dev/null 2>&1; then
    WAS_RUNNING=1
    pkill -fx "$LEGACY_INSTALLED/Contents/MacOS/TabStation" >/dev/null 2>&1 || true
    sleep 0.3
  fi
  rm -rf "$LEGACY_INSTALLED" "$ROOT/dist/TabStation.app"
  rm -rf "$INSTALLED"
  cp -R "$APP" "$INSTALLED"
  xattr -cr "$INSTALLED" 2>/dev/null || true
  if codesign --verify --deep --strict "$INSTALLED" >/dev/null 2>&1; then
    echo "Installed: $INSTALLED"
  else
    echo "Installed: $INSTALLED  (signature warning — see above)"
  fi
  if [[ "$WAS_RUNNING" == "1" && "${2:-}" != "--no-relaunch" ]]; then
    open "$INSTALLED"
    echo "Relaunched: $INSTALLED"
  fi
fi

echo
echo "Next steps:"
echo "  1. Grant Accessibility + Screen Recording in System Settings"
echo "     (the menu bar icon links straight to both panes), then choose"
echo "     'Relaunch AltDeck' from the same menu."
echo "  2. Hold the shortcut and tap Tab."
echo
echo "Run the installed copy, not dist/ — a leftover copy elsewhere will not"
echo "have today's changes."