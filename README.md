# jbl-bandbox

<p align="center"><img src="Stagehand/Art/logo.png" alt="Bandbox Stagehand" width="420"></p>

**Bandbox Stagehand** is a macOS and iPhone app that controls a **JBL BandBox Trio** over
Bluetooth LE, without the JBL One app. This repo also holds the tools and notes used to
reverse engineer the speaker's control protocol.

Not affiliated with or endorsed by JBL or Harman. JBL and BandBox are their trademarks.

## Bandbox Stagehand

`Stagehand/` is a SwiftUI app for the Mac and the iPhone: three landscape screens
with big buttons, meant to be used while holding a guitar. Swipe between them (touch,
trackpad or drag), tap the dots, or use ← / →.

1. **Tones and pedals**: four tone buttons (Clean, Crunch, Heavy, Lead; keys 1–4).
   Hold one, or right-click it, to pick which of the speaker's tones it selects.
   Above them, Comp, Dist, FX, Delay and Reverb turn on or off for the current tone.
2. **Tuner and mix**: the tuner (string, cents and frequency), the volume of the selected
   channel (1–4, channel 3 by default) and master volume.
3. **STEM AI**: on/off, the type of stem channels 1 and 2 (guitar, vocals, drums, off)
   and the volumes of both plus Others.

A white splash screen with the logo shows while the app connects to the speaker
(at most 10 s).

Volumes step one knob click (1/32) at a time and show as 0–100%. The display stays
awake while the app is open. The traffic log is behind the Log button.

Build and run (no Xcode project needed):

```bash
cd Stagehand && ./build.sh --run
```

macOS asks for Bluetooth permission on first launch, and again after each rebuild,
because every ad-hoc signed build counts as a new app.

### iPhone

The same controller runs on the iPhone (landscape, screen kept on while it's open, a haptic
tick on every press). It talks to the speaker directly; no Mac needed. With an iPhone
connected by cable (Developer Mode on), build and install it with:

```bash
cd Stagehand && ./ios-build.sh --install
```

It's signed with a free personal team, so iOS stops opening it after 7 days: run the
command again to reinstall. The first install needs Settings › General › VPN & Device
Management › trust the developer profile.

To sign with your own team, run it as `BANDBOX_TEAM=<your team id> ./ios-build.sh --install`
and change `PRODUCT_BUNDLE_IDENTIFIER` in `project.yml` to an ID of your own.

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
| `capture-speaker-controls.sh`, `capture-app-controls.sh` | The two guided sessions behind the latest notes: the speaker's own knobs, and the JBL app (recorded with PacketLogger) |
| `decode-pklg.py` | Decodes an iPhone PacketLogger `.pklg` capture into protocol messages |
| `decode-log.py` | Decodes a `BLEScan.app` log the same way |
| `discover-speaker.sh` | Early Wi-Fi/mDNS scan (the BandBox turned out to be Bluetooth-only) |

`captures/` holds the sessions the notes refer to: BLEScan logs and decoded PacketLogger
captures. Raw `.pklg` captures are kept out of git because they hold all of the phone's
Bluetooth traffic. Nearby devices and the speaker's serial number are removed from the
logs that are in git; check new ones for the same before committing them.
