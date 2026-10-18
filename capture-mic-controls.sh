#!/usr/bin/env bash
# Session 7: the Mac listens while you sweep channel 1's knobs with a mic plugged in
# (switch on mic): Delay, Reverb, Bass, Treble and Volume (there is no Mid knob), each all the way up,
# then all the way down. See polled-session.sh for what it polls.
# Close the JBL app (or turn off the phone's Bluetooth) and Stagehand first.
cd "$(dirname "$0")"
STEPS=("Plug the mic into channel 1, with its switch on mic. Then don't touch anything")
for knob in Delay Reverb Bass Treble Volume; do
  STEPS+=("Turn channel 1 $knob slowly all the way up" "Turn channel 1 $knob slowly all the way down")
done
STEPS+=("Done with the knobs. Set them back where you like them")
exec bash polled-session.sh captures/mic-controls "${STEPS[@]}"
