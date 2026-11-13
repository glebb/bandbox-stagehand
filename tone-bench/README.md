# tone-bench

Measures a BandBox's amps, cabs and knobs for Stagehand's Match amps, and checks the matches on the speaker.
Nothing here is needed to use Stagehand.

## What it needs

- The BandBox on the Mac by USB-C, a guitar (or just its cable) in channel 3, and nothing else talking to the
  speaker: quit Stagehand and the JBL app.
- `ToneBench.app` (`../build-tone-bench.sh`, then `open ../ToneBench.app`): the control channel on a local
  port. macOS asks once to allow Bluetooth for it.
- Python with numpy and scipy, and ffmpeg.

With `BENCH_INPUT="JBL BandBox Trio"` everything is silent: the bench turns on output to the computer with
direct monitor off (the DI) and reads the speaker's USB feed, whose first channel is the guitar channel after
its tone and its volume. It puts the tone, the volumes and the DI back at the end. Without `BENCH_INPUT` it
listens with the Mac's microphone instead, which works but is loud, slow and needs a quiet room.

## The test signal

There is no way to play a signal into the guitar input without a cable, so the bench uses what the input
already has: the guitar's idle noise. The Precision Drive at full raises it by 44 dB into a steady buzz, the
compressor at ratio 1 adds up to 18 dB more with its Output, and the Precision Drive's Level takes up to 14 dB
off. That is a signal over 32 dB of level, hot enough at the top to saturate every amp.

## The runs

```bash
BENCH_INPUT="JBL BandBox Trio" python measure.py usb-1 steps amps volume cabs eq   # ~10 minutes
BENCH_INPUT="JBL BandBox Trio" python measure.py usb-2 transfer                    # ~15 minutes
python analyse.py data/usb-1.jsonl data/usb-2.jsonl > ../Stagehand/Sources/Shared/SongTones/BandBoxCalibration.swift
../build-match-cli.sh
BENCH_INPUT="JBL BandBox Trio" python verify.py 1 15 22 17    # the tones in your Clean, Crunch, Heavy and Lead slots
```

`measure.py` writes a line per reading to `data/`. `analyse.py` makes Stagehand's tables from them.
`verify.py` plays each slot tone's amp and cab and then what Match amps makes of it for eleven game rigs, and
prints how far apart they are: 13 November 2026, within 1 dB for most and 2.8 dB at worst.

## What was learned about the speaker

- The amp's **Volume** is after everything that distorts and is the same on every amp: around 50, 20 is
  −15.6 dB, 100 is +12.1 dB.
- The **Precision Drive** is a clean boost up to at least +62 dB over a guitar's noise: +3.6 dB at Drive 0,
  +44 dB at 100. The **compressor's Output** is 0 to +18 dB, 0.18 dB a step.
- The **cabs** are within 2 dB of each other but for A Bass 8x10 (+3.8) and UK 2550 (−2.2); off is +4.1.
- American Gain Stack and US Metal are nearly the same amp by level and saturation.
- The **USB feed follows** the channel's volume (about 1.8 dB a step up to 8, less above), and also the
  master volume and the computer's playback volume, the wrong way round: with the master at 8 the feed was
  4.8 dB louder than at 16. A run has to leave those alone; the second run here had the playback volume
  turned on the way, 9 dB, and `analyse.py` puts that back from the first run.
- Changing the **pickup setting** mutes the channel for a few seconds.
- The feed clips at 0 dBFS with a hot tone and the channel's volume above about 16.

## What isn't measured

- **A guitar being played.** The tables say what an amp does at an input level; where a real guitar sits on
  that scale is `BandBoxCalibration.guitar`, an estimate (+8 dB over the plain test signal). Too low, and
  every matched tone is a little dirtier than meant; too high, cleaner.
- The compressor's threshold and ratio, the wahs, the gate, Bass Amp past its Drive, Acoustic Amp, Studio Bass.
- The tone knobs' effect on level is the mean of three amps, between 300 Hz and 6 kHz only.
- Whether a matched tone sounds like the game's, side by side. Played with Rocksmith it sounded right (13 November 2026).
