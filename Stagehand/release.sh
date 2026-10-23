#!/usr/bin/env bash
# Builds a Mac release: a universal Stagehand.app, zipped, with its SHA-256 and release notes.
# Usage: ./release.sh 0.2.0 [--publish]
#   --publish  also tags v0.2.0, pushes the tag and creates the GitHub release (needs gh).
# Without --publish nothing leaves this Mac: the files land in build/release/.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=${1:-}
PUBLISH=0
[[ "${2:-}" == "--publish" ]] && PUBLISH=1
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: ./release.sh X.Y.Z [--publish]" >&2
  exit 1
fi
TAG="v$VERSION"

if [[ -n "$(git status --porcelain)" ]]; then
  echo "the working tree has changes; commit them first" >&2
  exit 1
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && [[ "$(git rev-list -n1 "$TAG")" != "$(git rev-parse HEAD)" ]]; then
  echo "$TAG already exists on another commit" >&2
  exit 1
fi

VERSION="$VERSION" ./build.sh --universal

OUT=build/release
# A fixed name, so releases/latest/download/Stagehand-macOS.zip always gets the newest.
ZIP="$OUT/Stagehand-macOS.zip"
rm -rf "$OUT" && mkdir -p "$OUT"
# ditto keeps the code signature and extended attributes that a plain zip would lose.
ditto -c -k --sequesterRsrc --keepParent build/Stagehand.app "$ZIP"
(cd "$OUT" && shasum -a 256 "$(basename "$ZIP")" > SHA256SUMS.txt)
SHA=$(cut -d' ' -f1 "$OUT/SHA256SUMS.txt")

cat > "$OUT/notes.md" <<EOF
Bandbox Stagehand $VERSION for macOS 14 or later, Apple silicon and Intel.

### Install

1. Download \`$(basename "$ZIP")\` and open it; you get **Stagehand.app**. Move it to
   Applications (to update, replace the old one).
2. Open it. The app isn't notarized by Apple, so macOS blocks it the first time: open
   **System Settings › Privacy & Security**, scroll down and click **Open Anyway** next to
   Stagehand, then confirm. On older macOS versions, right-click (or Control-click) the app,
   choose **Open**, then **Open** again.
3. Allow Bluetooth when asked.

Full instructions are in the [README](https://github.com/glebb/bandbox-stagehand#readme).

SHA-256: \`$SHA\`

Not affiliated with or endorsed by JBL or Harman. Changing and deleting tones writes to the
speaker; use at your own risk.
EOF

lipo -archs build/Stagehand.app/Contents/MacOS/Stagehand
codesign --verify --strict build/Stagehand.app
echo "release files in $OUT:"
ls -l "$OUT"

if [[ $PUBLISH == 1 ]]; then
  command -v gh >/dev/null || { echo "gh isn't installed (brew install gh)" >&2; exit 1; }
  git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || git tag -a "$TAG" -m "Stagehand $VERSION"
  git push origin "$TAG"
  gh release create "$TAG" "$ZIP" "$OUT/SHA256SUMS.txt" \
    --title "Stagehand $VERSION" --notes-file "$OUT/notes.md" --generate-notes
else
  echo "check $OUT/notes.md, then publish with: ./release.sh $VERSION --publish"
fi
