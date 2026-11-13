#!/usr/bin/env bash
# Builds Stagehand/build/match-cli from tone-bench/match-cli.swift and Stagehand's own matching code, for tone-bench/verify.py.
set -euo pipefail
cd "$(dirname "$0")"
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
cp tone-bench/match-cli.swift "$BUILD/main.swift"   # the file with top-level code must be main.swift
mkdir -p Stagehand/build
S=Stagehand/Sources/Shared
swiftc -O "$BUILD/main.swift" $S/Protocol.swift $S/Effects.swift $S/SongTones/SongTonesRequest.swift $S/SongTones/GearMatch.swift \
  $S/SongTones/BandBoxCalibration.swift -o Stagehand/build/match-cli
echo "built Stagehand/build/match-cli"
