#!/usr/bin/env bash
# Session 1: the Mac listens while you use the speaker's own controls.
# Close the JBL app (or turn off the phone's Bluetooth) first.
cd "$(dirname "$0")"
GAP=${GAP:-15} bash guided-session.sh auto captures/speaker-controls \
  "Turn master volume all the way down" \
  "Turn master volume up slowly, one click at a time, all the way to the top" \
  "Turn master volume back down to a comfortable level" \
  "Turn channel 3 volume all the way down" \
  "Turn channel 3 volume up slowly, one click at a time, all the way to the top" \
  "Turn channel 3 volume back down to a comfortable level" \
  "Channel 1 volume up one click" \
  "Channel 1 volume down one click" \
  "Channel 2 volume up one click" \
  "Channel 2 volume down one click" \
  "Turn the tuner on" \
  "Play the open low E string and let it ring" \
  "Detune the low E clearly flat and play it" \
  "Tune the low E back up and play it in tune" \
  "Play the open A string and let it ring" \
  "Play the high E string and let it ring" \
  "Turn the tuner off" || exit 1
python3 -I decode-log.py captures/speaker-controls.listen.log > captures/speaker-controls.decoded.txt
echo "Decoded: captures/speaker-controls.decoded.txt"
