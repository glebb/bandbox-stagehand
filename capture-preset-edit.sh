#!/usr/bin/env bash
# Session 10: what the preset editor needs (see preset-editor-plan.md).
#
# listen: the Mac drives, you play. On guitar channel CH (default 3) it selects Feathered
#   Blues (0x0d), edits its delay time and its amp's first knob with 0x3445 op 04 (one param,
#   as the JBL app does in app-capture-6-delay), discards the edits with 0x3446 op 08 and goes
#   back to tone ORIG (default 0f). 0x3444 keeps showing the saved values, so only your ears
#   tell whether edits work. (A first run with op 01 blocks, 18:00, was not heard: op 01 only
#   sets bypass.) Close the JBL app and Stagehand first, guitar in CH.
#
# Every other area speaks prompts while you use the JBL app, like capture-app-features.sh.
# Record the iPhone's Bluetooth with PacketLogger at the same time, one .pklg per run, saved
# as captures/app-capture-6-<area>.pklg. Take an iPhone screenshot whenever asked: the
# knob names come from them. Edit Feathered Blues, so the other tones stay untouched.
#
# Usage: capture-preset-edit.sh <listen|gate|comp|dist|amp|cab|fx|delay|reverb|save>
# GAP=<seconds> sets the pause after each prompt (default 10).
cd "$(dirname "$0")"
AREA=${1:-}

# Prompts to sweep each knob of the open pedal; "skip it if there is none" covers models
# with fewer knobs. Knobs are counted left to right, top to bottom, the big one included.
# Counts are the model's param count in 0x3444 / the op 02 reply (app capture 4); the
# delay run asked for 3 and missed Sweep Echo's Mix and Time.
knobs() {
  local n
  for (( n = 1; n <= $1; n++ )); do
    K+=("Knob $n all the way down, skip it if there is none" "Knob $n all the way up" "Knob $n back to the middle")
  done
}

# One model of a pedal: switch to it, screenshot, sweep its knobs.
model() {  # model <name> <knob count>
  K+=("Switch the model to $1" "Take a screenshot")
  knobs "$2"
}

app() {  # app <prompts…>: a JBL app session for this area
  GAP=${GAP:-10} bash guided-session.sh none "captures/app-capture-6-$AREA" \
    "Select the Feathered Blues tone and open its preset page" "$@" \
    "Leave the preset page without saving, discard the changes"
}

K=()
case "$AREA" in
  listen) ;;
  gate)
    K+=("Open the Gate" "Take a screenshot" "Turn the Gate off" "Turn it on")
    knobs 2
    K+=("Switch the Gate to another model, if there is one" "Take a screenshot")
    app "${K[@]}" ;;
  comp)
    K+=("Open the Compressor" "Take a screenshot" "Turn the Compressor off" "Turn it on")
    knobs 4
    app "${K[@]}" ;;
  dist)
    K+=("Open the Auto-Wah pedal" "Take a screenshot")
    knobs 4
    model "Touch-Wah" 4
    model "Precision Drive" 3
    app "${K[@]}" ;;
  amp)
    K+=("Open the amp, Yellow Tweed" "Take a screenshot")
    knobs 5
    K+=("Open the amp model list" "Take a screenshot of the list")
    for n in 1 2 3 4 5 6 7 8 9 10; do
      K+=("Select amp number $n in the list, skip it if there is none" "Take a screenshot")
    done
    app "${K[@]}" ;;
  cab)
    K+=("Open the cabinet, UK 1960 4 by 12" "Take a screenshot" "Open the cabinet model list" "Take a screenshot of the list")
    for n in 1 2 3 4 5 6 7 8 9 10; do
      K+=("Select cabinet number $n in the list, skip it if there is none")
    done
    K+=("If the cabinet has any knobs, turn the first all the way down" "And all the way up")
    app "${K[@]}" ;;
  fx)
    K+=("Open the F X pedal, Echo Phase" "Take a screenshot")
    knobs 1
    model "Green Phaser" 3
    model "Notch Phaser" 3
    model "Minivibe" 3
    model "Tremolo" 4
    model "Chorus" 3
    model "Retro Shiver" 2
    model "Jetter Flanger" 4
    model "Grand Vibrato" 2
    app "${K[@]}" ;;
  delay)
    K+=("Open the delay pedal, Pure Echo" "Take a screenshot")
    knobs 3
    model "Analog Echo" 3
    model "Echopress 900" 3
    model "Sweep Echo" 5
    model "Sweet Echo" 3
    K+=("Switch back to Pure Echo" "If there is a tap tempo or a sync switch, use it now")
    app "${K[@]}" ;;
  reverb)
    K+=("Open the Reverb" "Take a screenshot" "Switch the Reverb to another model, if there is one")
    knobs 3
    app "${K[@]}" ;;
  save)
    GAP=${GAP:-12} bash guided-session.sh none "captures/app-capture-6-$AREA" \
      "Select the Feathered Blues tone and open its preset page" \
      "Turn the delay time all the way up" \
      "Save as a new tone named Test One" "Take a screenshot of each step if there is a dialog" \
      "Select another tone" "Select Test One" \
      "Open the preset page, turn the reverb off" \
      "Save as another new tone named Test Two" \
      "Rename Test Two to Test Three, if the app allows it" \
      "Delete Test Three, if the app allows it" \
      "Delete Test One, if the app allows it" \
      "Select Feathered Blues" "Open the preset page" \
      "Change the delay time, then leave the page and choose not to save" ;;
  *) echo "usage: $0 <listen|gate|comp|dist|amp|cab|fx|delay|reverb|save>"; exit 1 ;;
esac
[ "$AREA" = listen ] || exit 0

CH=${CH:-3}; ORIG=${ORIG:-0f}
OUT=captures/preset-edit-listen
CHX=$(printf %02x "$CH")

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
# Feathered Blues (probe-param-edit-0.log): delay slot 6 Pure Echo, params 1 time 250 ms,
# 2 feedback 34, 0 mix 9; amp slot 3 0x0506 Yellow Tweed, param 0 = 66.
# op 04: slot | model u16 | ff (bypass unchanged) | 01 | param u8 | float32 LE.
param() { msg 2 "3445:${CHX}0d04$1ff01$2"; }
DELAY=061400; AMP=030605
DISCARD=$(msg 2 "3446:${CHX}080dffff00")

SENDS=(
  "1:$(msg 2 3441:$CHX)"              "2:$(msg 2 3442:${CHX}0d)"
  "14:$(param $DELAY 0000004842)"     "14.3:$(param $DELAY 0100004844)"   # mix 50, time 800
  "24:$(param $DELAY 010000c842)"     "24.3:$(param $DELAY 0200007042)"   # time 100, feedback 60
  "34:$DISCARD"
  "44:$(param $AMP 000000c842)"       "54:$(param $AMP 0000000000)"       # knob 0 = 100, 0
  "64:$DISCARD"
  "72:$(msg 2 3442:$CHX$ORIG)"
)
PROMPTS=(
  "3|Connected. Guitar in channel $CH. Play short notes and keep playing"
  "6|This is Feathered Blues as saved"
  "13|Delay long and loud now"
  "23|Delay short, with more repeats"
  "33|Back to the saved tone"
  "43|Amp knob 1 at maximum"
  "53|Amp knob 1 at minimum"
  "63|Back to the saved tone"
  "72|Done. Tell Claude what you heard at each step"
)

now() { perl -MTime::HiRes=time -MPOSIX=strftime -e '$t=time; printf "%s.%03d", strftime("%H:%M:%S",localtime $t), ($t-int $t)*1000'; }
rm -f "$OUT.listen.log" "$OUT.markers.log"
open -W --stdout "$PWD/$OUT.listen.log" --stderr "$PWD/$OUT.listen.log" \
  BLEScan.app --args auto listen 78 com "${SENDS[@]}" &
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
