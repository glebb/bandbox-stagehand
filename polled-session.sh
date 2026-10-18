#!/usr/bin/env bash
# Guided capture that also polls: runs the BLE listener, sends a GET of the properties
# read on connect whose meaning is unknown and SET 0x3400 / 0x3402 / 0x3441 = 01, 02, 03
# (channel, pickup and tone queries per channel) every POLL seconds (default 3), so
# state changes show up even if the speaker sends no event, and speaks each prompt.
# Writes <out-prefix>.listen.log, .markers.log, .timeline.log and .decoded.txt.
# Usage: polled-session.sh <out-prefix> "action 1" "action 2" ...
# GAP=<seconds> sets the pause after each prompt (default 15).
# Close the JBL app (or turn off the phone's Bluetooth) and Stagehand first.
cd "$(dirname "$0")"
OUT=$1; shift
STEPS=("$@")
GAP=${GAP:-15}
POLL=${POLL:-3}

# Poll messages, built the way Stagehand's BandBoxProtocol does.
read -r GET_HEX SET_HEX < <(python3 -I - <<'EOF'
def le16(n): return [n & 0xff, n >> 8]
def frame(t, p): return bytes([0x00, 0xdd] + le16(t) + [1, 0] + le16(len(p)) + p).hex()
gets = [0x000c, 0x1008, 0x2c00, 0x2c01, 0x2c02, 0x2c03, 0x2c04, 0x2c05, 0x2c80,
        0x0c00, 0x3000, 0x3040, 0x3145, 0x3148, 0x3404, 0x3407, 0x31c3]
sets = []
for prop in (0x3400, 0x3402, 0x3441):
    for ch in (1, 2, 3):
        sets += le16(prop) + le16(1) + [ch]
print(frame(1, sum((le16(g) for g in gets), [])), frame(2, sets))
EOF
)

TOTAL=$(( ${#STEPS[@]} * (GAP + 4) + 20 ))  # say takes a few seconds per prompt
SENDS=()
for (( t = 1; t < TOTAL; t += POLL )); do
  SENDS+=("$t:$GET_HEX" "$(echo "$t + 0.5" | bc):$SET_HEX")
done

# guided-session.sh has no way to pass timed writes to BLEScan, so run
# the listener here with the polls and let guided-session.sh speak the prompts.
rm -f "$OUT.listen.log" "$OUT.markers.log"
open -W --stdout "$PWD/$OUT.listen.log" --stderr "$PWD/$OUT.listen.log" \
  BLEScan.app --args auto listen $(( TOTAL + 30 )) com "${SENDS[@]}" &
LPID=$!
for _ in $(seq 1 40); do
  grep -q "subscribed com" "$OUT.listen.log" 2>/dev/null && break
  grep -q "no device matched" "$OUT.listen.log" 2>/dev/null && { echo "speaker not found"; say "Speaker not found"; exit 1; }
  sleep 1
done
grep -q "subscribed com" "$OUT.listen.log" || { echo "never subscribed"; kill $LPID; exit 1; }

# A separate prefix: guided-session.sh deletes <prefix>.listen.log, which BLEScan is writing.
GAP=$GAP bash guided-session.sh none "$OUT-prompts" "${STEPS[@]}" > /dev/null
mv "$OUT-prompts.markers.log" "$OUT.markers.log"

pkill -f BLEScan.app/Contents/MacOS/BLEScan; wait $LPID 2>/dev/null
# Keep nearby devices out of git: drop every scan line but the speaker's.
sed -i '' '/^• /{/JBL BandBox Trio/!d;}' "$OUT.listen.log"
{ grep '^\[' "$OUT.listen.log" | sed 's/  |.*//'; cat "$OUT.markers.log"; } | sort > "$OUT.timeline.log"
python3 -I decode-log.py "$OUT.listen.log" > "$OUT.decoded.txt"
echo "Decoded: $OUT.decoded.txt"
