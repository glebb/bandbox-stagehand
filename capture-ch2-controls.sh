#!/usr/bin/env bash
# Session 8: channel 2's knobs. With a mic (switch on mic): Delay and Reverb up and
# down, to see whether they share 0x0c09 / 0x0c0a with channel 1, and Bass up. Then
# with line in: Bass, Mid and Treble up and down. Last, the mic goes back in, to see
# whether it kept its own EQ (bass still up) or shares the line input's.
# See polled-session.sh for what it polls.
# Close the JBL app (or turn off the phone's Bluetooth) and Stagehand first.
cd "$(dirname "$0")"
exec bash polled-session.sh captures/ch2-controls \
  "Plug the mic into channel 2, with its switch on mic. Then don't touch anything" \
  "Turn channel 2 Delay slowly all the way up" \
  "Turn channel 2 Delay slowly all the way down" \
  "Turn channel 2 Reverb slowly all the way up" \
  "Turn channel 2 Reverb slowly all the way down" \
  "Turn channel 2 Bass slowly all the way up, and leave it there" \
  "Unplug the mic, and set the channel 2 switch to line in" \
  "Plug the line in cable into channel 2" \
  "Turn channel 2 Bass slowly all the way up" \
  "Turn channel 2 Bass slowly all the way down" \
  "Turn channel 2 Mid slowly all the way up" \
  "Turn channel 2 Mid slowly all the way down" \
  "Turn channel 2 Treble slowly all the way up" \
  "Turn channel 2 Treble slowly all the way down" \
  "Unplug the line in cable, set the switch to mic, and plug the mic back in" \
  "Done. Set the knobs back where you like them"
