#!/usr/bin/env bash
# Builds BLEScan.app, the scanner/listener/sender used to reverse engineer the protocol.
# It must be an app bundle with a Bluetooth usage string, or macOS silently blocks CoreBluetooth.
#   open -W --stdout "$PWD/out.log" BLEScan.app --args auto listen 20 com ["<secs>:<hex>" ...]
set -euo pipefail
cd "$(dirname "$0")"
APP=BLEScan.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
swiftc ble-scan.swift -o "$APP/Contents/MacOS/BLEScan"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.blescan</string>
  <key>CFBundleName</key><string>BLEScan</string>
  <key>CFBundleExecutable</key><string>BLEScan</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>Scan for the JBL speaker's Bluetooth control service.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "built $APP"
