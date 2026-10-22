#!/usr/bin/env bash
# Runs Tests/main.swift: the code that needs no speaker or window (SysEx, song tones, planning).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
swiftc Tests/main.swift Sources/Shared/Protocol.swift Sources/Shared/Effects.swift Sources/Shared/ScratchTones.swift \
  Sources/macOS/MIDIMessage.swift -o build/tests
build/tests
