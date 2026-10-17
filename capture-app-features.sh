#!/usr/bin/env bash
# Session 4: speaks prompts and logs their times while you use the JBL app, one feature
# area per run so a missed step only costs that area. Record the iPhone's Bluetooth
# traffic with PacketLogger at the same time, one .pklg per run, saved as
# captures/app-capture-4-<area>.pklg.
# Usage: capture-app-features.sh <save|pedals|pickup|stem|pitch|drums|looper|eq>
# GAP=<seconds> sets the pause after each prompt (default 12).
cd "$(dirname "$0")"
AREA=${1:-}
OUT=captures/app-capture-4-$AREA
run() { GAP=${GAP:-12} bash guided-session.sh none "$OUT" "$@"; }

case "$AREA" in
  save) run \
    "Select the Brit Crunch tone" \
    "Turn Delay on" \
    "Save the tone, overwriting it" \
    "Select another tone" "Select Brit Crunch again" \
    "Turn Delay off" \
    "Turn Reverb on" \
    "Save the tone as a new tone, if the app allows it" \
    "Select another tone" "Select the tone you just saved" ;;
  pedals) run \
    "Select the Brit Crunch tone" \
    "Open the Distortion pedal" \
    "Switch the Distortion pedal to a different model" \
    "Switch it to another model" "Switch it back to the original model" \
    "Turn the first Distortion knob all the way down" \
    "Turn the same knob all the way up" "Turn it to the middle" \
    "Turn the second Distortion knob all the way down" "Turn it all the way up" \
    "Open the Delay pedal" \
    "Switch the Delay pedal to a different model" "Switch it back" \
    "Set Delay time to the minimum" "Set Delay time to the maximum" \
    "Open the Reverb pedal" \
    "Switch the Reverb pedal to a different model" "Switch it back" \
    "Open the F X pedal" \
    "Switch the F X pedal to a different model" "Switch it back" \
    "Open the Compressor pedal" \
    "Switch the Compressor to a different model" "Switch it back" \
    "Open the Amp" "Switch the Amp to a different model" "Switch it back" ;;
  pickup) run \
    "Set pickup type to Active" \
    "Set pickup type to Passive humbucker" \
    "Set pickup type to Single coil" \
    "Set pickup type back to what it was" ;;
  stem) run \
    "Turn Stem A I on" \
    "Turn karaoke mode on" \
    "Set vocals volume to 0 percent" "Set vocals volume to 100 percent" \
    "Set Others volume to 30 percent" \
    "Turn karaoke mode off" \
    "Turn Stem A I off" ;;
  pitch) run \
    "Set pitch shift to plus 1" "Set pitch shift to plus 5" \
    "Set pitch shift to minus 1" "Set pitch shift to minus 5" \
    "Set pitch shift back to 0" ;;
  drums) run \
    "Open the drum machine" "Start the drums" \
    "Change the drum pattern" "Change it again" \
    "Set tempo to the minimum" "Set tempo to the maximum" "Set tempo to 100" \
    "Set drum volume to 0 percent" "Set drum volume to 100 percent" \
    "Stop the drums" ;;
  looper) run \
    "Open the looper" \
    "Start recording a loop" "Stop recording, let it play" \
    "Start overdubbing" "Stop overdubbing" \
    "Undo the overdub, if possible" \
    "Stop the loop" "Play the loop again" \
    "Set loop volume to 30 percent" \
    "Clear the loop" ;;
  eq) run \
    "Open global E Q" \
    "Set the lowest band all the way down" "Set it all the way up" "Set it back to 0" \
    "Set the highest band all the way down" "Set it all the way up" "Set it back to 0" \
    "Reset global E Q, if possible" \
    "Open channel 4 E Q" \
    "Set the lowest band all the way down" "Set it all the way up" "Set it back to 0" \
    "Set the highest band all the way down" "Set it back to 0" ;;
  *) echo "usage: $0 <save|pedals|pickup|stem|pitch|drums|looper|eq>"; exit 1 ;;
esac
