# bandbox-stagehand

<p align="center"><img src="Stagehand/Art/logo.png" alt="Bandbox Stagehand" width="420"></p>

**Bandbox Stagehand** is a macOS and iPhone app that controls a **JBL BandBox Trio** over
Bluetooth LE, without the JBL One app. This repo also holds the tools and notes used to
reverse engineer the speaker's control protocol.

Not affiliated with or endorsed by JBL or Harman. JBL and BandBox are their trademarks.

Most of this project, the app as well as the protocol research, was done with AI: written
by an AI coding assistant, steered and tested by hand against the speaker.

## Why

The JBL One app does a lot: dozens of tones, pedals and amps, a full preset editor,
STEM AI. But it's a pain to use when you play songs that need different sounds. Going
from a clean verse to a distorted chorus, or switching a delay on for a solo, means
putting the guitar down and working through the app's screens on a phone.

Stagehand puts the sounds a song needs one press away: four big tone buttons per guitar,
the pedals right above them, and the same controls on the Mac keyboard or a MIDI
footswitch, so you can change sound without taking your hands off the guitar for long.

## What it does

- **Switch tones** with four big buttons per guitar input (Clean, Crunch, Heavy, Lead by
  default), each set to any of the speaker's tones and named as you like.
- **Turn pedals on and off** (compressor, distortion, FX, delay, reverb) and pick their
  models, then save the result into the tone.
- **Edit tones in depth** in a preset editor: the whole chain from gate to reverb, every
  model and knob, with save, save as, rename, delete and factory reset.
- **Tune and mix**: tuner (guitar strings or chromatic), pickup type, channel and master volumes.
- **STEM AI**: on/off, what the two stem channels hold, and their volumes.
- **DI to a computer**: with the BandBox as the computer's sound card over USB-C, the guitar goes
  to the computer and not to the speaker, while what the computer plays still comes out of the
  speaker. Optionally dry, on the Bypassed tone. Tried on a Trio with a Mac; Dry hasn't been.
- **Banks**: other sets of the four tone buttons (say Soft, Classic rock, Metal), switched in
  the footer or by MIDI.
- **Hands-free on the Mac**: number keys that work from any app, and MIDI control from a
  footswitch, keyboard or another app, with MIDI Learn.
- **Song tones** (optional, Mac): another app describes a song's tones in a MIDI message,
  and Stagehand builds a tone for each from your own and plays it on cue. The
  [RS Companion](https://github.com/glebb/rs-mac-companion) does this for Rocksmith songs.
- Runs on the **Mac and the iPhone**, talking to the speaker over Bluetooth; no JBL app or
  network needed.

**Scope.** Stagehand is a controller for the BandBox, and that's its whole job. Everything
from outside comes in through generic interfaces that any app or device can use: keys, MIDI
bindings, CC 90 for banks, and the documented Song tones message. Nothing in Stagehand depends
on one particular sender. Features beyond controlling the speaker, such as Song tones, are
optional, and with them off Stagehand is a plain controller.

## The screens

`Stagehand/` is a SwiftUI app for the Mac and the iPhone: landscape screens with big
buttons, meant to be used while holding a guitar. Swipe between them (touch, trackpad or
drag), tap the dots, or use ← / →.

1. **Tones and pedals**, one screen per guitar input: channel 1 (with its switch on guitar)
   and channel 3 each have their own tone and pedals. A screen shows for each channel with a
   guitar plugged in (channel 3 when none is), and the footer shows which channel it
   controls (CH 1 / CH 3) next to the page dots. Each channel has its own four tone slots
   (Clean, Crunch, Heavy, Lead; keys 1–4 on the Mac); channel 1 starts as a copy of channel 3's.
   Hold one, or right-click it, to rename it, to pick which of the speaker's tones it
   selects, or to open its tone in the preset editor. Above them, Comp, Dist, FX, Delay
   and Reverb turn on or off for the current tone (keys 5–9 and MIDI do the same). Hold
   Dist, FX or Delay, or right-click it, to pick its model, by the JBL app's names (Dist
   holds the wahs and Precision Drive). Pedal and model changes are saved into the tone
   right away, unless the tone has unsaved changes from the preset editor: then they join
   those, for the editor's Save or Discard.
   **Banks** are other sets of the four slots (say Soft, Classic rock, Metal), for both
   channels: *Banks* in the footer makes one from the slots as they are, then picks, renames
   or deletes them. CC 90 picks one by MIDI, and a song's style can pick one (Song tones,
   below). With one bank nothing else changes; with more, the footer names the current one.
   While a song's tones play, a strip above the pedals names the song and its tones, and the
   slot the playing tone is built on lights up.
2. **Tuner and mix**: a channel picker across the top (1–4, each labelled with what its
   switch is set to: Guitar, Mic, Line, USB/BT; it starts on the guitar's channel) chooses
   the channel the rest of the screen shows: its pickup type (Active, Humbucker, Single
   coil; only for channel 3, or channel 1 with its switch on guitar), the tuner (string, cents and frequency) and its volume.
   Master volume is on the right. Hold the tuner (or right-click it on the Mac) to switch it
   between **Strings**, which matches a guitar's six strings in standard tuning, and
   **Chromatic**, which names any note with its octave (D2, C♯3), for drop D, E♭ or a bass. That's
   the speaker's own setting, as in the JBL app's tuner settings. **Chromatic hasn't been tried on
   a speaker yet.**
3. **STEM AI**: on/off, the type of stem channels 1 and 2 (guitar, vocals, drums, off)
   and the volumes of both plus Others.
4. **DI**: for playing into a computer (Rocksmith, a DAW) with the BandBox as its sound card
   over USB-C. **DI** sends the guitar to the computer only: the speaker stops playing it, and
   what the computer plays still comes out of the speaker. It's what the JBL app's Output page
   does with *PC* picked and *Direct Monitor Mode* off, and it shows whether a computer is on the
   USB port. **Dry** plays the Bypassed tone on the guitar channels in use, so the computer gets
   the guitar as it comes in; off goes back to the tones they had (or the Clean slot). On the
   right is the volume of what the speaker plays (channel 4's), titled by its source, so a phone
   playing over Bluetooth instead of the computer shows there. While DI is on the footer says
   **DI on**; the speaker keeps it until it's switched off, also after Stagehand quits.
   **Tried on a Trio** (2026-11-12, a Mac over USB-C): with DI on the Mac's BandBox input got the
   guitar on inputs 1 and 2 (3 and 4 stayed silent), the speaker didn't play it, and it still
   played the Mac's sound; DI off put the speaker back as it was. With output set to the phone,
   as the speaker was before, the Mac's input was silent even with the guitar playing, so off
   DI the computer gets no guitar at all. Dry hasn't been tried. The commands come from the JBL
   app (see [app-teardown.md](app-teardown.md)), and the screen shows what the speaker reports back.
   **Known issue, not Stagehand's**: as a Mac's sound card the BandBox stalls for about 50 ms
   every 5–25 seconds, which you hear in Rocksmith. Its USB input now and then doesn't answer
   (macOS's `usbaudiod` logs `transaction status error: 0xe00002ed`, "not responding"), and macOS
   restarts the device's audio, input and output. It happens with DI on or off, without
   Rocksmith or Loopback, with the Mac and the speaker on mains power or battery, and at any
   buffer size, though small buffers make it more frequent (6
   stalls in 75 s at 64 frames, 3 at 512). The audio between stalls is clean. Not yet tried:
   another cable or port, and newer speaker firmware. To see it:
   `/usr/bin/log show --last 10m --info --debug --predicate 'process == "usbaudiod"' | grep "status error"`.
5. **Preset editor**: the whole chain of the tone a guitar channel plays: gate,
   compressor, distortion, amp, cabinet, FX, delay and reverb, joined like a pedalboard
   (amber when on). Tap a slot to show its models (by the JBL app's names: 11 amps, 12
   cabinets, 9 FX…) and its knobs; drag a knob up or down to turn it, and the power button
   switches the pedal on or off. Tap the tone's name to edit another tone (it plays, so
   you hear what you edit); with guitars in both channels, CH 1 / CH 3 picks the channel.
   **Save** writes the changes into the tone, **Save as…** makes a new tone with a name
   and category (then offers to put it on a tone slot), and the ⋯ menu discards the
   changes, renames or deletes a tone you saved, or puts a factory tone back to its
   factory settings. Changes that aren't saved are lost when the tone changes, as on the
   tones page; the editor asks first when you pick another tone.

A white splash screen with the logo shows while the app connects to the speaker
(at most 10 s).

Volumes step one knob click (1/32) at a time and show as 0–100%. The display stays
awake while the app is open. The traffic log is behind the Log button.

## Hands-free control (Mac)

On the Mac, 1–4 select the tone slots and 5–9 switch Comp, Dist, FX, Delay and Reverb of
channel 3 (or of channel 1 when only it has a guitar); with Shift, of channel 1.
The **Keys 1–9** switch in the footer makes them work from any app, so you can keep
another app in front and play with one free finger. While it's on (amber), those keys
don't type digits anywhere else; turn it off to type normally. It stays as you left it.
No permission is needed.

The Mac app also takes **MIDI**, from any connected device or app, with Stagehand in
front or not. By default, on any MIDI channel, Program Change 0–3 select the tone slots
and CC 80–84 switch Comp, Dist, FX, Delay and Reverb, as keys 1–9 do; PC 4–7 and CC 85–89
do the same for channel 1. The **MIDI** button in the footer (its dot flashes on each
message) opens the list: click a binding, then press a switch or key, to use that instead
(MIDI Learn). Pedals work with momentary and latching switches alike; the ⋯ menu limits a
binding to one MIDI channel, or sets a pedal to Follow (64 and up is on) so it matches a
latching switch. CC 90 picks a bank by its value (0 the first, 1 the next…). Each message
Stagehand acts on shows in the Log. Without a controller,
`swift midi-send.swift pc 2 press 81` sends test messages from a virtual source.
If the Mac's MIDI server hangs (the Yamaha Steinberg USB MIDI driver hung it when a BandBox
was plugged in over USB-C), Stagehand still opens and works; only MIDI waits for the server.

### Song tones

Optional and Mac only. Switch it on in the MIDI settings.

Another app can describe a song's tones in one SysEx message (manufacturer 0x7D, then JSON),
and Stagehand makes a tone for each and plays them by Program Change. The
[RS Companion](https://github.com/glebb/rs-mac-companion) sends one as a Rocksmith song loads; a
setlist or backing-track app could as well. Each tone gives:
- a category (Clean, Crunch, Heavy or Lead), which is the slot it starts from;
- its delay, modulation and reverb in plain terms (tape or analog delay, chorus, phaser…);
- the Program Change that plays it.

The song itself gives a style, which names the bank the slots come from. The format is at the
top of `Sources/Shared/SongTones/SongTonesRequest.swift`. The RS Companion's
[spec](https://github.com/glebb/rs-mac-companion/blob/main/docs/song-tone-messages.md) is
written from the sender's side.

How a song tone is built:
1. The song's style names a bank, say Metal. Stagehand switches to it, and makes it first as a
   copy of Main if there's none by that name (the Log says so).
2. Each tone starts from the slot of its category in that bank: a Heavy tone in a Metal song
   from the Metal bank's Heavy slot. The slot gives the amp, drive and levels.
3. The song's delay, modulation and reverb go on top, and the result is saved as "Song 1"–"Song 5".
   Your slot tones stay as they are.
4. During the song, each tone's Program Change plays its Song tone.

So until you set up a bank's slots (to sound soft, classic rock or metal, say), the songs with
that style sound as with Main.

**Match amps** (off by default, under Song tones in the MIDI settings) also gives a driven tone the
amp nearest the song's, if the message says which: the amp's family and how driven the tone is pick one
of the JBL app's models, at its defaults. Marshall-style amps get UK Crunch or British Lead, Fender-style
Yellow Tweed or Vintage Drive, and high-gain ones Vintage Drive or US Metal. Clean tones, basses, DIs, amps
it doesn't know and templates on Acoustic Amp, Studio Bass or Bass Amp keep the slot's amp. It costs one
more write per tone. **It hasn't been tried on a speaker.** The plan's rule that levels come from your
slots doesn't hold for these tones: the level is the model's default, and nothing has measured how those
compare, so start with the volume down.

Stagehand turns the effects into the BandBox's pedals (tape delay → Echopress 900, analog →
Analog Echo, chorus → Chorus, and so on, mixes kept at most 35) and fills a tone of its own for
each: user tones "Song 1"–"Song 5", made on first use and left out of the tone menus. It plays
the slot's tone, sets the pedals, saves it into the song tone and drops the edits, so the tones
in your slots stay as they are. That takes about half a second a tone, and the channel jumps
between your slots meanwhile. The Program Changes the message names then play them (unless you
bind those to something else; before they're ready, their slots), and the tones page shows the
song with the playing tone lit. Every other setting comes from your slots, so the levels stay yours. Off, Stagehand
ignores the messages, leaves those Program Changes to the bindings and makes no tones. Try it
without another app:
`swift midi-send.swift sysex Tests/song-tones.json pc 8 wait 8 pc 9 wait 8 pc 10`
(`Sources/Shared/SongTones/`; how it came about: [song-tones-plan.md](song-tones-plan.md)).

## Not yet

Ideas, not promises:
- **MIDI on the iPhone.** CoreMIDI runs there too, but Bluetooth MIDI needs its own pairing
  screen. That would also bring Song tones to the iPhone.
- **More MIDI actions:** an expression pedal for volume, next / previous tone, cycling a
  pedal's model, and lights on the controller that show what's on
  ([midi-plan.md](midi-plan.md)).
- **More of the JBL app's features:** the looper, drums and metronome, and EQ.
  The JBL app names all their properties ([app-teardown.md](app-teardown.md)); none is captured
  or tried yet (`capture-app-features.sh`).

## Getting it

### Mac

#### Install

1. Download [`Stagehand-macOS.zip`](https://github.com/glebb/bandbox-stagehand/releases/latest/download/Stagehand-macOS.zip)
   from the [releases](https://github.com/glebb/bandbox-stagehand/releases) page and open it;
   you get **Stagehand.app**. Move it to Applications (macOS 14 or later, Apple silicon or Intel).
2. Open it. The first time, macOS says it can't verify the developer (the app isn't notarized
   by Apple). Go to **System Settings → Privacy & Security**, scroll down, click **Open
   Anyway** next to Stagehand, and confirm. On older macOS versions, right-click (or
   Control-click) the app, choose **Open**, then **Open** again.
3. Allow Bluetooth when asked, and turn on the speaker.

To update, download the new zip and replace the app in Applications. To uninstall, move it to
the Trash; its settings are in
`~/Library/Preferences/io.github.glebb.bandbox-stagehand.plist`.

#### Building it yourself

No Xcode project needed:

```bash
cd Stagehand && ./build.sh --run
```

macOS asks for Bluetooth permission on first launch, and again after each rebuild,
because every ad-hoc signed build counts as a new app.

#### Making a release

`./release.sh X.Y.Z` builds a universal app (Apple silicon and Intel) with that version,
and puts the zip, its SHA-256 and draft release notes in `Stagehand/build/release/`. It
needs a clean working tree. Read the notes, then `./release.sh X.Y.Z --publish` tags
`vX.Y.Z`, pushes the tag and creates the GitHub release with the zip (needs
[gh](https://cli.github.com), signed in).

The Mac and iPhone apps share their version (`version.sh`): the latest `v*` tag, so
builds after a release keep its number until the next one, and a build number that is
the commit count.

The app is ad-hoc signed, not notarized, so macOS blocks it the first time it opens
after downloading; the release notes explain **Open Anyway** in Privacy & Security.

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

## Code and artwork

The code is shared:
- `Sources/Shared` holds the protocol, client and screens.
- `Sources/Shared/SongTones` holds the optional Song tones feature: the message, the filler
  and the song strip. The client gives it only generic hooks (reserved tones, record
  observers, raw sends).
- `Sources/macOS` and `Sources/iOS` each hold an app's entry point. The Mac's also holds the
  global keys and the MIDI input and sheet.

`project.yml` describes the iPhone project for XcodeGen. `./test.sh` runs the tests of the parts
that need no speaker (`Tests/main.swift`).

How the bigger features were planned: [midi-plan.md](midi-plan.md),
[preset-editor-plan.md](preset-editor-plan.md), [song-tones-plan.md](song-tones-plan.md).

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
| `scratch-probe.swift`, `build-scratch-probe.sh` | `ScratchProbe.app`: what song tones need (reading and saving a tone that isn't playing, write speed, how many user tones fit), on its own "Probe" tones, which it deletes |
| `guided-session.sh` | Runs the listener and speaks prompts aloud, so each button press lines up with its message |
| `capture-speaker-controls.sh`, `capture-app-controls.sh` | Guided sessions behind the notes: the speaker's own knobs, and the JBL app (recorded with PacketLogger) |
| `polled-session.sh` | Like `guided-session.sh`, but also polls the per-channel queries and unknown properties every few seconds; the two sessions below use it |
| `capture-mic-controls.sh` | Guided session sweeping channel 1's mic knobs (Delay, Reverb, Bass, Treble, Volume) |
| `capture-tuner.sh` | Keeps the tuner on while one guitar moves from channel 3 to channel 1, to see which input it hears |
| `capture-ch1-guitar.sh` | The Mac switches channel 1's tone and toggles its delay while you play, then runs the tuner |
| `capture-ch2-controls.sh` | Guided session for channel 2's knobs: mic Delay and Reverb, then line-in Bass, Mid and Treble |
| `capture-inputs.sh` | Guided session plugging a mic, guitar and line-in into each channel, polling the per-channel queries while you do |
| `capture-preset-edit.sh` | The preset editor's research: the Mac edits a tone while you listen (`listen`), and one JBL app area per run (gate, comp, dist, amp, cab, fx, delay, reverb, save) |
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
