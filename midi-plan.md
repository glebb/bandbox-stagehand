# MIDI control plan

The Mac app listens to MIDI and does what the tones page's buttons do: select tone buttons
1–4 and switch Comp, Dist, FX, Delay and Reverb, of the primary guitar channel or of
channel 1. It works with another app in front, like *Keys 1–9: everywhere*. CoreMIDI needs
no permission or entitlement, so the ad-hoc signed `build.sh` stays as it is.

There's no particular controller to aim at, so the defaults should suit most footswitch
boards, keyboards and DAWs, and MIDI Learn covers the rest.

## Decisions
- A MIDI tone change behaves like keys 1–4: it switches tone without asking, even with
  unsaved edits in the preset editor. A footswitch press never waits on a dialog.
- Mac only. CoreMIDI runs on the iPhone too, but Bluetooth MIDI there needs its own
  pairing screen; later.
- Not now (each fits on top of `StageAction` later): an expression pedal for volume,
  next / previous tone, cycling a pedal's model, LED feedback back to the controller.

## Step 1: one action list for keys and MIDI (`Shared/Commands.swift`) — done
`StageAction` (`.tone(slot, target)`, `.pedal(pedal, target)`, target `.primary` or
`.channel1`) and `BandBoxClient.perform(_:assignments:on:)`. The in-app keys
(`channelKeys`) and `GlobalHotKeys` both call it instead of repeating the logic. No change
in behaviour.

## Step 2: MIDI input (`macOS/MIDIInput.swift`, `MIDIMessage.swift`) — done
- `MIDIClientCreateWithBlock`, an input port with the MIDI 1.0 protocol, connected to every
  source; the notify block reconnects when devices come or go.
- Parses Program Change, Control Change and Note On (velocity 0 = Note Off, ignored).
- Hops from CoreMIDI's thread to the main actor before acting.
- Publishes source names and the last message, for the UI.
- Parsing and the switch logic are pure functions, checkable without hardware.
- Each acted-on message shows in the Log (`MIDI CC 81 = 127 · ch 1 → Dist`).

Done 2026-10-18 with the default map and both pedal modes from step 3 wired in: parser
and switch logic checked offline; the whole path checked against the speaker with
`midi-send.swift` (a source appearing and going away, PC tones on both channels,
momentary CC presses, unbound notes ignored).

## Step 3: mapping — done
- Default map, omni:
  - PC 0–3: tone buttons of the primary channel; PC 4–7: of channel 1.
  - CC 80–84: Comp, Dist, FX, Delay, Reverb of the primary channel; CC 85–89: of channel 1.
  - No default notes: Learn covers keyboards and pads.
- Pedal modes, per binding:
  - **Auto** (default), works with momentary and latching switches alike: a value ≥ 64
    toggles; a value < 64 toggles too, unless it's a momentary switch letting go. Each
    controller's kind is learned from timing (high to low under 0.5 s: momentary; over
    2 s: latching); until then, low within 1 s of high is a release. Note On and PC
    always toggle.
  - **Follow**: value ≥ 64 on, < 64 off; for latching switches that should never drift
    out of sync with the pedal.
- MIDI Learn: tap an action, press the switch; the next PC / CC / Note binds to it, and
  replaces any other action bound to the same message. A binding is omni or one channel.
- Saved in UserDefaults as JSON, like `ToneAssignments`.

## Step 4: UI — done
- A **MIDI** button in the footer next to Log (Mac only), with a dot that flashes amber on
  incoming messages.
- The MIDI sheet: on / off, connected sources, the 18 actions with their bindings
  (`PC 2`, `CC 81 · ch 1`), Learn, Auto / Follow for pedals, Reset to defaults.
- Two columns, like plain and Shift keys: "Guitar channel (CH 3, or CH 1 if it's the only
  guitar)" and "Channel 1". While only channel 1 has a guitar, a note says both columns
  control it.

Done 2026-10-18 and tried in the app with `midi-send.swift`: Learn (the learning press and
its release don't act; the old binding is replaced), saving across a relaunch, MIDI off,
Reset to Defaults. The ⋯ menu (channel, mode, clear) wasn't clicked through.

## Step 5: testing and docs — done but for a real controller
- `midi-send.swift`: a virtual CoreMIDI source that sends PC / CC sequences, to test the
  whole path without hardware (the IAC Driver works too).
- Checked with the speaker through `midi-send.swift`; a hardware controller is still to try.
- README: the MIDI paragraph in the Mac part.
