#!/usr/bin/env bash
# Runs Tests/main.swift: the code that needs no speaker or window (SysEx, song tones, planning, banks).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
# Everything but the app's entry point, which would clash with the tests' top-level code.
swiftc Tests/main.swift Sources/Shared/*.swift Sources/Shared/SongTones/*.swift $(ls Sources/macOS/*.swift | grep -v StagehandApp.swift) \
  -o build/stagehand-tests
build/stagehand-tests
