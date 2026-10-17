#!/usr/bin/env bash
# Builds Stagehand.app (no Xcode project needed). Usage: ./build.sh [--run]
set -euo pipefail
cd "$(dirname "$0")"

APP=build/Stagehand.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Fonts/Yellowtail-Regular.ttf "$APP/Contents/Resources/"

# App icon: every size an .icns needs, scaled down from the 1024 px artwork.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Art/AppIcon-mac.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Art/AppIcon-mac.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -parse-as-library \
  -target arm64-apple-macos14.0 \
  Sources/Shared/*.swift Sources/macOS/*.swift \
  -o "$APP/Contents/MacOS/Stagehand"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.bandbox-stagehand</string>
  <key>CFBundleName</key><string>Stagehand</string>
  <key>CFBundleDisplayName</key><string>Bandbox Stagehand</string>
  <key>CFBundleExecutable</key><string>Stagehand</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>ATSApplicationFontsPath</key><string>.</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Stagehand connects to your JBL BandBox Trio over Bluetooth to change presets, STEM AI, the tuner and volume.</string>
</dict></plist>
EOF

codesign --force --sign - "$APP"
echo "built $APP"

if [[ "${1:-}" == "--run" ]]; then
  open "$APP"
fi
