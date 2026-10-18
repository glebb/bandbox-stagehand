# bandbox-stagehand

<p align="center"><img src="Stagehand/Art/logo.png" alt="Bandbox Stagehand" width="420"></p>

**Bandbox Stagehand** is a macOS and iPhone app that controls a **JBL BandBox Trio** over
Bluetooth LE, without the JBL One app. This repo also holds the tools and notes used to
reverse engineer the speaker's control protocol.

Not affiliated with or endorsed by JBL or Harman. JBL and BandBox are their trademarks.

## Bandbox Stagehand

`Stagehand/` is a SwiftUI app for the Mac and the iPhone: landscape screens with big
buttons, meant to be used while holding a guitar. Swipe between them (touch, trackpad or
drag), tap the dots, or use ← / →.

1. **Tones and pedals**, one screen per guitar input: channel 1 (with its switch on guitar)
   and channel 3 each have their own tone and pedals. A screen shows for each channel with a
   guitar plugged in (channel 3 when none is), and the footer shows which channel it
   controls (CH 1 / CH 3) next to the page dots. Each channel has its own four tone buttons
   (Clean, Crunch, Heavy, Lead; keys 1–4 on the Mac); channel 1 starts as a copy of channel 3's.
   Hold one, or right-click it, to rename it, to pick which of the speaker's tones it
   selects, or to save the pedals into that tone on the speaker (only while it's
   playing). Above them, Comp, Dist, FX, Delay and Reverb turn on or off for the current
   tone. Hold Dist, FX or Delay, or right-click it, to pick its model, by the JBL app's
   names (Dist holds the wahs and Precision Drive). Pedal and model changes are lost
   when the tone changes, unless saved.
2. **Tuner and mix**: a channel picker across the top (1–4, each labelled with what its
   switch is set to: Guitar, Mic, Line, USB/BT) chooses the channel the rest of the screen
   shows: its pickup type (Active, Humbucker, Single coil; only for channel 3, or channel 1
   with its switch on guitar), the tuner (string, cents and frequency) and its volume.
   Master volume is on the right.
3. **STEM AI**: on/off, the type of stem channels 1 and 2 (guitar, vocals, drums, off)
   and the volumes of both plus Others.

A white splash screen with the logo shows while the app connects to the speaker
(at most 10 s).

Volumes step one knob click (1/32) at a time and show as 0–100%. The display stays
awake while the app is open. The traffic log is behind the Log button.

On the Mac, 1–4 select the tone buttons and 5–9 switch Comp, Dist, FX, Delay and Reverb of
channel 3 (or of channel 1 when only it has a guitar); with Shift, of channel 1.
The **Keys 1–9** switch in the footer makes them work from any app, so you can keep
another app in front and play with one free finger. While it's on (amber), those keys
don't type digits anywhere else; turn it off to type normally. It stays as you left it.
No permission is needed.

Build and run (no Xcode project needed):

```bash
cd Stagehand && ./build.sh --run
```

macOS asks for Bluetooth permission on first launch, and again after each rebuild,
because every ad-hoc signed build counts as a new app.

### iPhone

The same controller runs on the iPhone (landscape, screen kept on while it's open, a haptic
tick on every press). It talks to the speaker directly; no Mac needed.

Signing needs your Apple team ID (a free personal team works) and a bundle ID of your own.
Copy `Stagehand/signing.env.example` to `Stagehand/signing.env` and fill in both; the file
stays out of git. Then, with the iPhone connected by cable (Developer Mode on):

```bash
cd Stagehand && ./ios-build.sh --install
```

With a free team, iOS stops opening the app after 7 days: run the command again to
reinstall. The first install needs Settings › General › VPN & Device Management › trust
the developer profile. Without `signing.env`, `./ios-build.sh` only checks that the app
compiles.

#### Reinstalling automatically

The Mac can do the weekly reinstall itself, over Wi-Fi once the iPhone has been connected
by cable and shows up in Xcode's Devices window:

```bash
cd Stagehand && ./auto-install.sh --enable
```

This adds a launch agent that runs `auto-install.sh` every day at 05:00, or when the Mac
next wakes if it was asleep then. Once 5 days have passed since the last install, it
rebuilds the app and installs it without opening it; otherwise it does nothing. The phone
needs to be on the same Wi-Fi (or on the cable) and the Mac signed in to Xcode. A failed
install, or an iPhone still out of reach a day before expiry, shows a notification. Each
run is logged in `~/Library/Logs/Stagehand-install.log`.

`./auto-install.sh --now` reinstalls right away, and `./auto-install.sh --disable` removes
the launch agent.

#### Alternative: AltStore

[AltStore Classic](https://altstore.io) re-signs the app over Wi-Fi before the 7 days run
out, as long as the iPhone and the Mac running AltServer are on the same network at least
once a week. It's still a free 7-day signature, renewed for you.

1. Install AltServer on the Mac and AltStore on the iPhone, following
   [AltStore's guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos)
   (Finder's "Show this iPhone when on Wi-Fi" must be on). It asks for an Apple ID; a
   separate one just for this is a good idea.
2. Delete any copy installed with `--install`: AltStore signs its own copy under a
   slightly different bundle ID.
3. Build the app as an `.ipa`, which AltStore signs itself:

   ```bash
   cd Stagehand && ./ios-build.sh --ipa
   ```

4. Get `build/Stagehand.ipa` onto the iPhone (AirDrop it and save to Files), then in
   AltStore › My Apps tap **+** and pick it.

Build and add a new `.ipa` only when the app changes. With free signing, AltStore itself
takes one of the three sideloaded-app slots.

### Code and artwork

The code is shared: `Sources/Shared` holds the protocol, client and screens, and
`Sources/macOS` / `Sources/iOS` each hold an app's entry point. `project.yml` describes
the iPhone project for XcodeGen.

The logo is set in [Yellowtail](https://fonts.google.com/specimen/Yellowtail)
(`Fonts/`, Apache 2.0). `swift render-art.swift` redraws the iPhone and Mac icons and
`Art/logo.png` from it.

The speaker accepts only one controller at a time. Close the JBL app on your phone
(or turn off the phone's Bluetooth) first, or the speaker keeps dropping the Mac.

## Protocol

See [protocol-notes.md](protocol-notes.md) for the message format and every property
found so far. In short: GATT service `65786365-…-2E636F6D0000` ("excelpoint.com"),
write to `…0002`, notifications on `…0001`, messages framed as
`00 dd | type | frag | length | payload` with GET / SET / EVENT / ACK types.

## Tools

| File | Purpose |
|---|---|
| `ble-scan.swift`, `build-blescan.sh` | Scanner/listener/sender (`BLEScan.app`): finds the speaker, dumps GATT, logs notifications, sends timed writes |
| `guided-session.sh` | Runs the listener and speaks prompts aloud, so each button press lines up with its message |
| `capture-speaker-controls.sh`, `capture-app-controls.sh` | Guided sessions behind the notes: the speaker's own knobs, and the JBL app (recorded with PacketLogger) |
| `polled-session.sh` | Like `guided-session.sh`, but also polls the per-channel queries and unknown properties every few seconds; the two sessions below use it |
| `capture-mic-controls.sh` | Guided session sweeping channel 1's mic knobs (Delay, Reverb, Bass, Treble, Volume) |
| `capture-tuner.sh` | Keeps the tuner on while one guitar moves from channel 3 to channel 1, to see which input it hears |
| `capture-ch1-guitar.sh` | The Mac switches channel 1's tone and toggles its delay while you play, then runs the tuner |
| `capture-ch2-controls.sh` | Guided session for channel 2's knobs: mic Delay and Reverb, then line-in Bass, Mid and Treble |
| `capture-inputs.sh` | Guided session plugging a mic, guitar and line-in into each channel, polling the per-channel queries while you do |
| `capture-app-features.sh` | Prompts for one JBL app feature area per run (save, pedals, pickup, stem, pitch, drums, looper, eq), for the features not mapped yet |
| `decode-pklg.py` | Decodes an iPhone PacketLogger `.pklg` capture into protocol messages |
| `decode-log.py` | Decodes a `BLEScan.app` log the same way |
| `discover-speaker.sh` | Early Wi-Fi/mDNS scan (the BandBox turned out to be Bluetooth-only) |

`captures/` holds the sessions the notes refer to: BLEScan logs and decoded PacketLogger
captures. Raw `.pklg` captures are kept out of git because they hold all of the phone's
Bluetooth traffic. Nearby devices and the speaker's serial number are removed from the
logs that are in git; check new ones for the same before committing them.

## License

MIT, see [LICENSE](LICENSE). The Yellowtail font in `Stagehand/Fonts/` is Apache 2.0.
