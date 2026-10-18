#!/usr/bin/env bash
# Session 9: a guitar on channel 1. While you play, the Mac switches channel 1's tone
# from 0x1b ("Bypassed", what it was on) to tone 01 and back, turns that tone's delay
# (slot 6) on and off with 0x3445 addressed to channel 01, runs the tuner, and asks you
# to press the speaker's preset button. Polls SET 0x3441 = 01 / 03 every 3 s to see
# which channel's tone changed. The delay block is copied from probe-ch1-tone.log;
# re-read it if channel 1 is on another tone.
# Close the JBL app (or turn off the phone's Bluetooth) and Stagehand first.
cd "$(dirname "$0")"
OUT=captures/ch1-guitar

msg() {  # msg <type> <id:hexvalue>...  → one framed message
  python3 -I - "$@" <<'PY'
import sys
def le16(n): return [n & 0xff, n >> 8]
t, recs = int(sys.argv[1]), sys.argv[2:]
p = []
for r in recs:
    i, v = r.split(":"); v = bytes.fromhex(v)
    p += le16(int(i, 16)) + le16(len(v)) + list(v)
print(bytes([0, 0xdd] + le16(t) + [1, 0] + le16(len(p)) + p).hex())
PY
}
DELAY=0614000103010000e14302000050420000003042  # slot 6, model 0x14, bypassed, 3 params
DELAY_ON=${DELAY:0:6}00${DELAY:8}
POLL=$(msg 2 3441:01 3441:03)
SENDS=(
  "12:$(msg 2 3442:0101)"            "22:$(msg 2 3442:011b)"
  "32:$(msg 2 3445:011b01$DELAY_ON)" "42:$(msg 2 3445:011b01$DELAY)"
  "52:$(msg 2 3100:01)" "57:$(msg 2 3100:01)" "62:$(msg 2 3100:01)"
  "67:$(msg 2 3804:0100)" "67.3:$(msg 2 3100:00)"
  "86:$(msg 2 3442:011b 3442:0301)"  # put both channels back on their tones
)
for (( t = 2; t < 90; t += 3 )); do SENDS+=("$t.5:$POLL"); done

PROMPTS=(
  "3|Connected. Guitar in channel 1, switch on guitar. Start playing and keep playing"
  "11|Tone change now"
  "21|Back to the first tone"
  "31|Delay on now"
  "41|Delay off now"
  "51|Tuner on. Play the open low E string and let it ring"
  "71|Tuner off. Press the speaker's preset button once"
  "84|Done. Thank you"
)

now() { perl -MTime::HiRes=time -MPOSIX=strftime -e '$t=time; printf "%s.%03d", strftime("%H:%M:%S",localtime $t), ($t-int $t)*1000'; }
rm -f "$OUT.listen.log" "$OUT.markers.log"
open -W --stdout "$PWD/$OUT.listen.log" --stderr "$PWD/$OUT.listen.log" \
  BLEScan.app --args auto listen 95 com "${SENDS[@]}" &
LPID=$!
for _ in $(seq 1 200); do
  grep -q "subscribed com" "$OUT.listen.log" 2>/dev/null && break
  grep -q "DISCONNECTED" "$OUT.listen.log" 2>/dev/null && { say "The speaker dropped the Mac"; pkill -f BLEScan.app/Contents/MacOS/BLEScan; exit 1; }
  sleep 0.2
done
grep -q "subscribed com" "$OUT.listen.log" || { say "Speaker not found"; pkill -f BLEScan.app/Contents/MacOS/BLEScan; exit 1; }
START=$(perl -MTime::HiRes=time -e 'print time')

for p in "${PROMPTS[@]}"; do
  at=${p%%|*}; text=${p#*|}
  perl -MTime::HiRes=time,sleep -e 'my $d = $ARGV[0] + $ARGV[1] - time; sleep $d if $d > 0' "$START" "$at"
  echo "[$(now)] >>> $text" >> "$OUT.markers.log"
  say "$text" &
done
wait $LPID 2>/dev/null
# Keep nearby devices out of git: drop every scan line but the speaker's.
sed -i '' '/^• /{/JBL BandBox Trio/!d;}' "$OUT.listen.log"
{ grep '^\[' "$OUT.listen.log" | sed 's/  |.*//'; cat "$OUT.markers.log"; } | sort > "$OUT.timeline.log"
python3 -I decode-log.py "$OUT.listen.log" > "$OUT.decoded.txt"
echo "Decoded: $OUT.decoded.txt"
