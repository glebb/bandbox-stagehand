#!/usr/bin/env bash
# Builds the iPhone app and, with --install, puts it on a connected iPhone.
# Usage: ./ios-build.sh [--install | --ipa]   (BANDBOX_LAUNCH=0 to install without opening the app)
# Signing comes from signing.env (copy signing.env.example): BANDBOX_TEAM and BANDBOX_BUNDLE_ID.
# Without a team it only checks that the app compiles, unsigned.
# --ipa builds an unsigned release build/Stagehand.ipa for AltStore, which signs it itself.
# The version comes from version.sh, the same as the Mac app's.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f signing.env ]]; then
  overrides=$(declare -p BANDBOX_TEAM BANDBOX_BUNDLE_ID 2>/dev/null || true)
  source signing.env
  eval "$overrides"   # the environment wins over the file
fi
BANDBOX_TEAM=${BANDBOX_TEAM:-}
BANDBOX_BUNDLE_ID=${BANDBOX_BUNDLE_ID:-local.bandbox-stagehand}

source version.sh
VERSION_SETTINGS=(MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER")

xcodegen generate --quiet

if [[ "${1:-}" == "--ipa" ]]; then
  xcodebuild -project Stagehand.xcodeproj -scheme Stagehand -configuration Release \
    -destination 'generic/platform=iOS' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO "${VERSION_SETTINGS[@]}" build -quiet
  rm -rf build/ipa build/Stagehand.ipa
  mkdir -p build/ipa/Payload
  cp -R build/ios/Build/Products/Release-iphoneos/Stagehand.app build/ipa/Payload/
  (cd build/ipa && zip -qry ../Stagehand.ipa Payload)
  echo "built build/Stagehand.ipa"
  exit 0
fi

if [[ -z "$BANDBOX_TEAM" ]]; then
  [[ "${1:-}" == "--install" ]] && { echo "set BANDBOX_TEAM in signing.env to install (see signing.env.example)"; exit 1; }
  xcodebuild -project Stagehand.xcodeproj -scheme Stagehand -configuration Debug \
    -destination 'generic/platform=iOS' -derivedDataPath build/ios CODE_SIGNING_ALLOWED=NO "${VERSION_SETTINGS[@]}" build -quiet
  echo "built (unsigned) build/ios/Build/Products/Debug-iphoneos/Stagehand.app"
  exit 0
fi

xcodebuild -project Stagehand.xcodeproj -scheme Stagehand -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath build/ios \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$BANDBOX_TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BANDBOX_BUNDLE_ID" \
  "${VERSION_SETTINGS[@]}" build -quiet
APP=build/ios/Build/Products/Debug-iphoneos/Stagehand.app
echo "built $APP $VERSION ($BUILD_NUMBER)"

if [[ "${1:-}" == "--install" ]]; then
  DEVICE=$(xcrun devicectl list devices 2>/dev/null | grep -E 'iPhone.* (available|connected)' \
    | grep -oE '[0-9A-F]{8}-[0-9A-F]{16}' | head -1)
  [[ -n "$DEVICE" ]] || { echo "no connected iPhone found"; exit 1; }
  xcrun devicectl device install app --device "$DEVICE" "$APP"
  if [[ "${BANDBOX_LAUNCH:-1}" != 0 ]]; then
    xcrun devicectl device process launch --device "$DEVICE" "$BANDBOX_BUNDLE_ID" || true
  fi
fi
