#!/bin/zsh
set -e
cd "$(dirname "$0")"

APP_NAME="AI Usage"
APP="/Applications/$APP_NAME.app"

echo "→ Compilando (release)…"
swift build -c release

echo "→ Empaquetando $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/AIUsage" "$APP/Contents/MacOS/$APP_NAME"

if [[ ! -f .build/AppIcon.icns ]]; then
  echo "→ Generando icono…"
  if swift scripts/make_icon.swift .build/icon_1024.png 2>/dev/null; then
    ICONSET=".build/AppIcon.iconset"
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    for s in 16 32 128 256 512; do
      sips -z $s $s .build/icon_1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
      d=$((s * 2))
      sips -z $d $d .build/icon_1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o .build/AppIcon.icns
  else
    echo "  (icono omitido)"
  fi
fi
[[ -f .build/AppIcon.icns ]] && cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>AI Usage</string>
    <key>CFBundleDisplayName</key>
    <string>AI Usage</string>
    <key>CFBundleIdentifier</key>
    <string>dev.aitor.ai-usage</string>
    <key>CFBundleExecutable</key>
    <string>AI Usage</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

IDENTITY="${CODESIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | grep -m1 "Apple Development" | awk '{print $2}')}"
if [[ -n "$IDENTITY" ]]; then
  echo "→ Firmando ($IDENTITY)…"
  codesign --force --sign "$IDENTITY" "$APP"
else
  echo "→ Firmando (ad hoc)…"
  codesign --force --sign - "$APP"
fi

echo "✓ Instalada en: $APP"
echo "  Ábrela con: open \"$APP\""
