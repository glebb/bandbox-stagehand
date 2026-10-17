#!/usr/bin/env bash
# Guided capture: run the BLE listener, speak each action aloud, log a timestamped
# marker for it, then merge markers and notifications into one timeline.
# Usage: guided-session.sh <device-id-prefix-or-name|auto|none> <out-prefix> "action 1" "action 2" ...
# Target "none" only speaks and logs the prompts, for lining them up with an iPhone
# PacketLogger capture while the JBL app holds the connection.
# GAP=<seconds> sets the pause after each prompt (default 10).
set -u
cd "$(dirname "$0")"

TARGET=$1; OUT=$2; shift 2
GAP=${GAP:-10}
LISTEN=$(( ${#@} * GAP + 30 ))

now() { perl -MTime::HiRes=time -MPOSIX=strftime -e '$t=time; printf "%s.%03d", strftime("%H:%M:%S",localtime $t), ($t-int $t)*1000'; }

rm -f "$OUT.listen.log" "$OUT.markers.log"

if [ "$TARGET" = none ]; then
  say "Get ready."
  sleep 3
  for action in "$@"; do
    echo "[$(now)] >>> $action" >> "$OUT.markers.log"
    say "$action"
    sleep "$GAP"
  done
  say "Done. Thank you."
  cat "$OUT.markers.log"
  exit 0
fi

open -W --stdout "$PWD/$OUT.listen.log" --stderr "$PWD/$OUT.listen.log" \
  BLEScan.app --args "$TARGET" listen "$LISTEN" com &
LPID=$!

# Wait until subscribed (or the scan gave up).
for _ in $(seq 1 40); do
  grep -q "subscribed com" "$OUT.listen.log" 2>/dev/null && break
  grep -q "no device matched" "$OUT.listen.log" 2>/dev/null && { echo "speaker not found"; say "Speaker not found"; exit 1; }
  sleep 1
done
grep -q "subscribed com" "$OUT.listen.log" || { echo "never subscribed"; kill $LPID; exit 1; }

say "Connected. Get ready."
sleep 3
for action in "$@"; do
  echo "[$(now)] >>> $action" >> "$OUT.markers.log"
  say "$action"
  sleep "$GAP"
done
say "Done. Thank you."

# Stop the listener early; we have what we need.
pkill -f BLEScan.app/Contents/MacOS/BLEScan; wait $LPID 2>/dev/null

# Merge into one timeline sorted by timestamp.
{ grep '^\[' "$OUT.listen.log" | sed 's/  |.*//'; cat "$OUT.markers.log"; } | sort > "$OUT.timeline.log"
cat "$OUT.timeline.log"
