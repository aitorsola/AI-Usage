#!/bin/zsh
set -e
cd "$(dirname "$0")"

APP_NAME="AI Usage"
DERIVED=".build/xcode"

echo "→ Generando icono (asset catalog)…"
ICONSET="Resources/Assets.xcassets/AppIcon.appiconset"
mkdir -p "$ICONSET"
mkdir -p .build
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

echo "→ Generando proyecto Xcode (xcodegen)…"
xcodegen generate

echo "→ Generando proyecto y compilando (xcodebuild, sin firmar)…"
xcodebuild -project AIUsage.xcodeproj -scheme AIUsage -configuration Release \
  -derivedDataPath "$DERIVED" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  build | tail -25

BUILT="$DERIVED/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$BUILT" ]]; then
  echo "✗ No se encontró el .app compilado en $BUILT"; exit 1
fi

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}')}"
if [[ -z "$IDENTITY" ]]; then IDENTITY="-"; fi
echo "→ Firmando a mano ($IDENTITY): widget primero, luego la app…"
codesign --force --sign "$IDENTITY" --entitlements Signing/Widget.entitlements \
  "$BUILT/Contents/PlugIns/AIUsageWidget.appex"
codesign --force --sign "$IDENTITY" --entitlements Signing/App.entitlements "$BUILT"
echo "→ Verificando firma…"
codesign --verify --deep --strict --verbose=1 "$BUILT" 2>&1 | tail -3 || true

echo "→ Instalando en /Applications/$APP_NAME.app"
rm -rf "/Applications/$APP_NAME.app"
cp -R "$BUILT" "/Applications/$APP_NAME.app"
echo "✓ Instalada. Widget embebido en Contents/PlugIns/AIUsageWidget.appex"
