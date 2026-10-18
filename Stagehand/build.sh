#!/usr/bin/env bash
# Builds Stagehand.app (no Xcode project needed). Usage: ./build.sh [--run] [--universal]
#   --universal  Apple silicon and Intel in one app (release.sh uses it); otherwise this Mac's only.
# The version comes from VERSION, else the latest v* git tag, else 0.0.0.
set -euo pipefail
cd "$(dirname "$0")"

RUN=0 UNIVERSAL=0
for arg in "$@"; do
  case "$arg" in
    --run) RUN=1 ;;
    --universal) UNIVERSAL=1 ;;
    *) echo "unknown option $arg" >&2; exit 1 ;;
  esac
done

VERSION=${VERSION:-$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null | sed 's/^v//' || true)}
VERSION=${VERSION:-0.0.0}
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)   # grows with every commit

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

if [[ $UNIVERSAL == 1 ]]; then ARCHS="arm64 x86_64"; else ARCHS=$(uname -m); fi
BINARIES=()
for arch in $ARCHS; do
  swiftc -O -parse-as-library \
    -target "$arch-apple-macos14.0" \
    Sources/Shared/*.swift Sources/macOS/*.swift \
    -o "build/Stagehand-$arch"
  BINARIES+=("build/Stagehand-$arch")
done
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Stagehand"
rm -f "${BINARIES[@]}"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>io.github.glebb.bandbox-stagehand</string>
  <key>CFBundleName</key><string>Stagehand</string>
  <key>CFBundleDisplayName</key><string>Bandbox Stagehand</string>
  <key>CFBundleExecutable</key><string>Stagehand</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>ATSApplicationFontsPath</key><string>.</string>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Stagehand connects to your JBL BandBox Trio over Bluetooth to change tones, pedals, volumes, STEM AI and the tuner.</string>
</dict></plist>
EOF

codesign --force --sign - "$APP"
echo "built $APP $VERSION ($BUILD_NUMBER, $ARCHS)"

if [[ $RUN == 1 ]]; then
  open "$APP"
fi
