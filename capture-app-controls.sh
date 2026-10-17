#!/usr/bin/env bash
# Session 2: speaks prompts and logs their times while you use the JBL app.
# Record the iPhone's Bluetooth traffic with PacketLogger at the same time.
cd "$(dirname "$0")"
GAP=${GAP:-10} bash guided-session.sh none captures/app-controls \
  "Turn Compressor on" "Turn Compressor off" \
  "Turn Distortion on" "Turn Distortion off" \
  "Turn F X on" "Turn F X off" \
  "Turn Delay on" "Turn Delay off" \
  "Turn Reverb on" "Turn Reverb off" \
  "Set master volume to 0 percent" "Set master volume to 25 percent" \
  "Set master volume to 50 percent" "Set master volume to 100 percent" \
  "Set master volume back to a comfortable level" \
  "Set channel 3 volume to 0 percent" "Set channel 3 volume to 25 percent" \
  "Set channel 3 volume to 50 percent" "Set channel 3 volume to 100 percent" \
  "Set channel 3 volume back to a comfortable level" \
  "Turn Stem A I on" \
  "Set stem channel 1 to Guitar" "Set stem channel 1 to Vocals" \
  "Set stem channel 1 to Drums" "Set stem channel 1 to Off" \
  "Set stem channel 1 back to Vocals" "Set stem channel 2 to Drums" \
  "Set stem channel 1 volume to 30 percent" "Set stem channel 1 volume to 70 percent" \
  "Set stem channel 2 volume to 30 percent" "Set stem channel 2 volume to 70 percent" \
  "Set Others volume to 30 percent" "Set Others volume to 70 percent" \
  "Turn Stem A I off"
