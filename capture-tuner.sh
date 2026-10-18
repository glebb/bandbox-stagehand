#!/usr/bin/env bash
# Session 10: which input the tuner listens to. The Mac keeps the tuner on (SET 0x3100 = 01
# every 5 s) while one guitar moves from channel 3 to channel 1, with a different string on
# each (low E on channel 3, A on channel 1) and the speaker's channel selection switched at
# every step. Polls SET 0x3400 = 1–3 every 3 s for what is plugged in.
# Close the JBL app (or turn off the phone's Bluetooth) and Stagehand first.
cd "$(dirname "$0")"
OUT=captures/tuner
GAP=${GAP:-18}

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

STEPS=(
  "Plug the guitar into channel 3, and select channel 3 on the speaker. Play the open low E string and let it ring"
  "Select channel 1 on the speaker. Keep playing the low E string"
  "Select channel 3 again. Keep playing the low E string"
  "Unplug the guitar. Set the channel 1 switch to guitar and plug the guitar into channel 1"
  "Play the open A string and let it ring"
  "Select channel 1 on the speaker. Keep playing the A string"
  "Select channel 3 on the speaker. Keep playing the A string"
  "Done. Thank you"
)
TOTAL=$(( 3 + ${#STEPS[@]} * GAP ))

ON=$(msg 2 3100:01) ; POLL=$(msg 2 3400:01 3400:02 3400:03)
SENDS=("1:$ON" "1.3:$(msg 2 3804:0102)")
for (( t = 6; t < TOTAL - GAP; t += 5 )); do SENDS+=("$t:$ON"); done
for (( t = 2; t < TOTAL; t += 3 )); do SENDS+=("$t.5:$POLL"); done
SENDS+=("$(( TOTAL - GAP + 2 )):$(msg 2 3804:0100)" "$(( TOTAL - GAP + 2 )).3:$(msg 2 3100:00)")

now() { perl -MTime::HiRes=time -MPOSIX=strftime -e '$t=time; printf "%s.%03d", strftime("%H:%M:%S",localtime $t), ($t-int $t)*1000'; }
rm -f "$OUT.listen.log" "$OUT.markers.log"
open -W --stdout "$PWD/$OUT.listen.log" --stderr "$PWD/$OUT.listen.log" \
  BLEScan.app --args auto listen $(( TOTAL + 5 )) com "${SENDS[@]}" &
LPID=$!
for _ in $(seq 1 200); do
  grep -q "subscribed com" "$OUT.listen.log" 2>/dev/null && break
  grep -q "DISCONNECTED" "$OUT.listen.log" 2>/dev/null && { say "The speaker dropped the Mac"; pkill -f BLEScan.app/Contents/MacOS/BLEScan; exit 1; }
  sleep 0.2
done
grep -q "subscribed com" "$OUT.listen.log" || { say "Speaker not found"; pkill -f BLEScan.app/Contents/MacOS/BLEScan; exit 1; }
START=$(perl -MTime::HiRes=time -e 'print time')

at=3
for text in "${STEPS[@]}"; do
  perl -MTime::HiRes=time,sleep -e 'my $d = $ARGV[0] + $ARGV[1] - time; sleep $d if $d > 0' "$START" "$at"
  echo "[$(now)] >>> $text" >> "$OUT.markers.log"
  say "$text" &
  at=$(( at + GAP ))
done
wait $LPID 2>/dev/null
# Keep nearby devices out of git: drop every scan line but the speaker's.
sed -i '' '/^• /{/JBL BandBox Trio/!d;}' "$OUT.listen.log"
{ grep '^\[' "$OUT.listen.log" | sed 's/  |.*//'; cat "$OUT.markers.log"; } | sort > "$OUT.timeline.log"
python3 -I decode-log.py "$OUT.listen.log" > "$OUT.decoded.txt"
echo "Decoded: $OUT.decoded.txt"
