#!/bin/zsh
# Build, sign with Developer ID, notarize and package AI Usage as a drag-to-install .dmg.
#
# One-time setup (only you can do these — they need your Apple account):
#   1. Create the Developer ID Application certificate:
#      Xcode → Settings → Accounts → your team → Manage Certificates… → + → Developer ID Application
#   2. Store notarization credentials in a keychain profile:
#      xcrun notarytool store-credentials AIUsage-notary \
#        --apple-id "<your-apple-id>" --team-id SK4CMEFH7T --password "<app-specific-password>"
#
# Then just run:  ./release.sh
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="AI Usage"
TEAM_ID="${TEAM_ID:-SK4CMEFH7T}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AIUsage-notary}"
DERIVED=".build/xcode-release"
DIST="dist"
DMG="$DIST/AI-Usage.dmg"

# --- 0) Preconditions -------------------------------------------------------
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | grep "$TEAM_ID" | head -1 | awk '{print $2}')
if [[ -z "$IDENTITY" ]]; then
  echo "✗ No 'Developer ID Application' certificate for team $TEAM_ID in the keychain."
  echo "  Create it: Xcode → Settings → Accounts → your team → Manage Certificates… → + → Developer ID Application"
  exit 1
fi
echo "→ Developer ID identity: $IDENTITY"

# --- 1) App icon asset catalog ---------------------------------------------
echo "→ Generating app icon…"
ICONSET="Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET" .build
swift scripts/make_icon.swift .build/icon_1024.png
for base in 16 32 128 256 512; do
  d=$((base * 2))
  sips -z $base $base .build/icon_1024.png --out "$ICONSET/icon_${base}x${base}.png" >/dev/null
  sips -z $d $d .build/icon_1024.png --out "$ICONSET/icon_${base}x${base}@2x.png" >/dev/null
done
cat > "$ICONSET/Contents.json" <<'JSON'
{
  "images" : [
    { "idiom" : "mac", "scale" : "1x", "size" : "16x16", "filename" : "icon_16x16.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "16x16", "filename" : "icon_16x16@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "32x32", "filename" : "icon_32x32.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "32x32", "filename" : "icon_32x32@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "128x128", "filename" : "icon_128x128.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "128x128", "filename" : "icon_128x128@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "256x256", "filename" : "icon_256x256.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "256x256", "filename" : "icon_256x256@2x.png" },
    { "idiom" : "mac", "scale" : "1x", "size" : "512x512", "filename" : "icon_512x512.png" },
    { "idiom" : "mac", "scale" : "2x", "size" : "512x512", "filename" : "icon_512x512@2x.png" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON

# --- 2) Build a universal (arm64 + x86_64) release, unsigned ----------------
echo "→ Generating project + building universal release…"
xcodegen generate
rm -rf "$DERIVED"
xcodebuild -project AIUsage.xcodeproj -scheme AIUsage -configuration Release \
  -derivedDataPath "$DERIVED" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build | tail -5

BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
[[ -d "$BUILT" ]] || { echo "✗ Build product not found at $BUILT"; exit 1; }

# --- 3) Sign with Developer ID + hardened runtime (widget first, then app) --
echo "→ Signing (hardened runtime, secure timestamp)…"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" --entitlements Signing/Widget.entitlements \
  "$BUILT/Contents/PlugIns/AIUsageWidget.appex"
codesign --force --options runtime --timestamp \
  --sign "$IDENTITY" --entitlements Signing/App.entitlements \
  "$BUILT"
codesign --verify --deep --strict --verbose=1 "$BUILT" 2>&1 | tail -2

# Set SKIP_NOTARIZE=1 to build + sign + package without notarizing (dry run).
if [[ -n "${SKIP_NOTARIZE:-}" ]]; then
  echo "→ SKIP_NOTARIZE set — building the .dmg without notarizing."
  mkdir -p "$DIST"
  STAGING=$(mktemp -d)
  cp -R "$BUILT" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  rm -f "$DMG"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGING"
  echo "✓ Built (unnotarized) → $DMG"
  echo "  Note: this .dmg is NOT notarized — Gatekeeper will block it on other Macs. Re-run without SKIP_NOTARIZE for a shippable build."
  exit 0
fi

# --- 4) Notarize the app, then staple the ticket ----------------------------
echo "→ Notarizing app (this can take a few minutes)…"
mkdir -p "$DIST"
ZIP="$DIST/AI-Usage-app.zip"
ditto -c -k --keepParent "$BUILT" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$BUILT"
rm -f "$ZIP"

# --- 5) Build the drag-to-install .dmg --------------------------------------
echo "→ Building .dmg…"
STAGING=$(mktemp -d)
cp -R "$BUILT" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

# --- 6) Notarize + staple the .dmg too --------------------------------------
echo "→ Notarizing .dmg…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$BUILT/Contents/Info.plist" 2>/dev/null || echo "1.0")
echo "✓ Done → $DMG"
echo "  Verify:  spctl -a -t open --context context:primary-signature -v \"$DMG\""
echo "  Release: gh release create v$VERSION \"$DMG\" --title \"AI Usage $VERSION\" --notes \"…\""
