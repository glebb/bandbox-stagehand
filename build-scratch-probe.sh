#!/usr/bin/env bash
# Builds ScratchProbe.app from scratch-probe.swift and Stagehand's protocol code. Like BLEScan it
# must be an app bundle with a Bluetooth usage string, or macOS silently blocks CoreBluetooth.
#   open -W --stdout "$PWD/captures/scratch-probe.log" ScratchProbe.app --args [CH] [CAP]
set -euo pipefail
cd "$(dirname "$0")"
APP=ScratchProbe.app
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
cp scratch-probe.swift "$BUILD/main.swift"   # the file with top-level code must be main.swift
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
swiftc -O "$BUILD/main.swift" Stagehand/Sources/Shared/Protocol.swift Stagehand/Sources/Shared/Effects.swift \
  -o "$APP/Contents/MacOS/ScratchProbe"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.scratchprobe</string>
  <key>CFBundleName</key><string>ScratchProbe</string>
  <key>CFBundleExecutable</key><string>ScratchProbe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Talk to the JBL speaker to test how its tones can be edited.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"
