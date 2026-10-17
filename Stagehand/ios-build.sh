#!/usr/bin/env bash
# Builds the iPhone app and, with --install, puts it on a connected iPhone.
# Usage: ./ios-build.sh [--install | --ipa]   (BANDBOX_TEAM=<team id> to sign with another team,
# BANDBOX_TEAM= to only check that the app compiles, unsigned)
# --ipa builds an unsigned release build/Stagehand.ipa for AltStore, which signs it itself.
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate --quiet
BANDBOX_TEAM=${BANDBOX_TEAM-ABCDE12345}

if [[ "${1:-}" == "--ipa" ]]; then
  xcodebuild -project Stagehand.xcodeproj -scheme Stagehand -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build -quiet
  rm -rf build/ipa build/Stagehand.ipa
  mkdir -p build/ipa/Payload
  cp -R build/ios/Build/Products/Release-iphoneos/Stagehand.app build/ipa/Payload/
  (cd build/ipa && zip -qry ../Stagehand.ipa Payload)
  echo "built build/Stagehand.ipa"
  exit 0
fi

if [[ -z "${BANDBOX_TEAM:-}" ]]; then
  xcodebuild -project Stagehand.xcodeproj -scheme Stagehand -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO build -quiet
  echo "built (unsigned) build/ios/Build/Products/Debug-iphoneos/Stagehand.app"
  exit 0
fi

xcodebuild -project Stagehand.xcodeproj -scheme Stagehand -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/ios \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$BANDBOX_TEAM" build -quiet
APP=build/ios/Build/Products/Debug-iphoneos/Stagehand.app
echo "built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -E 'iPhone.*(available|connected)' \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
  [[ -n "$DEVICE" ]] || { echo "no connected iPhone found"; exit 1; }
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  xcrun devicectl device process launch --device "$DEVICE" local.bandbox-stagehand || true
fi
