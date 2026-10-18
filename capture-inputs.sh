#!/usr/bin/env bash
# Session 6: the Mac listens while you plug inputs into channels 1–3 and flip the
# channel 1 and 2 switches. See polled-session.sh for what it polls.
# Close the JBL app (or turn off the phone's Bluetooth) and Stagehand first.
cd "$(dirname "$0")"
exec bash polled-session.sh captures/inputs \
  "Nothing plugged in. Don't touch anything" \
  "Set the channel 1 switch to mic" \
  "Plug the mic into channel 1" \
  "Unplug the mic" \
  "Set the channel 1 switch to guitar" \
  "Plug the guitar into channel 1" \
  "Unplug the guitar" \
  "Set the channel 2 switch to line in" \
  "Plug the line in cable into channel 2" \
  "Unplug the line in cable" \
  "Set the channel 2 switch to mic" \
  "Plug the mic into channel 2" \
  "Unplug the mic" \
  "Plug the guitar into channel 3" \
  "Unplug the guitar"
