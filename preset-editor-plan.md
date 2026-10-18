# Preset editor plan

A view for editing a tone in depth: the whole signal chain, each slot's model and its
parameters, then saving over the tone or as a new one. The tones screen stays the quick
view (pick a tone, switch pedals on and off); the editor goes deeper. The JBL app's
*Esiasetus* page (the chain drawn as pedals, amp and cab joined by a cable) is the reference.

## Protocol: known and missing

| | Status |
|---|---|
| A tone's 8 blocks (0x3444: slot, model, bypass, params) | Parsed; params kept as raw bytes |
| Bypass (0x3445 op 01) and model swap (op 02) | Done for comp, dist, FX, delay, reverb |
| Save into the same tone (0x3446 op 04, target ff) | Done |
| Changing a parameter value | Probably op 01 with new floats; probe from the Mac |
| Parameter names, ranges and units per model | Only Pure Echo and Precision Drive known |
| Amp models and names | Mapped: 11 amps, op 03 between guitar amps, op 02 for Acoustic / Studio Bass |
| Cab models and names | Mapped: 12 cabs, op 03, no params |
| Gate (slot 0) | Has knobs in the JBL app; models unknown |
| Save as a new tone (target ID, name) | Not captured |
| Discard edits (0x3446 op 08) | Probably; unconfirmed |

## Phase 0: protocol research
1. Mac probe: resend a block with op 01 and one float changed; check the echo and that
   0x3444 (or the sound) shows the change; try op 08 to discard.
2. `capture-preset-edit.sh`, a guided JBL app session per area: sweep every knob of every
   model min → max, step through amp and cab models, the gate, save as a new name,
   rename / delete a user tone, leave without saving.
3. Screenshots of each pedal page in the JBL app for knob names, units and order.
4. Record the findings in `protocol-notes.md`.

Done so far (2026-10-18, `captures/probe-param-edit-*.log`): op 01 with a changed float is
accepted and echoed; op 08 discards and is answered with 0x3442. **0x3444 returns the saved
tone, not the unsaved edits**, so Stagehand must keep the edited blocks itself: the
speaker can't tell it what the knobs are at after an edit. Feathered Blues (0x0d) has the
gate on, model 0x1c, 2 params. **op 01 with new floats is not heard** (`capture-preset-edit.sh listen`, guitar on channel 1):
op 01 applies only the bypass byte. **op 04 sets one parameter** (`ch NN 04 slot model ff 01
param f32`, app-capture-6-delay), **verified by ear from the Mac**, and op 08 audibly discards.
The delay models are mapped. Next: the other JBL app areas (gate, comp, dist, amp, cab, FX,
reverb) and save as.

## Phase 1: model layer (`Protocol.swift`)
- `EffectBlock.params` becomes `[EffectParam]` (`id u8`, `value Float`); `bytes` builds from them.
- `EffectSlot` covers all 8 slots (gate, comp, dist, amp, cab, FX, delay, reverb) with their
  models; `Pedal` stays as the tones screen's quick-switch subset.
- `EffectCatalog`: model → `[ParamSpec]` (name, range, unit, step, format). A parameter
  missing from it shows as a generic knob over its raw value, so the editor works before
  the research is complete.

## Phase 2: client (`BandBoxClient.swift`)
- `setParam(slot:param:value:channel:)`: optimistic update + op 04 with that one param; while a knob is
  dragged, coalesce writes (latest value, about every 50 ms).
- `setPedal` / `setModel` for every slot.
- `savedDetails[channel]`, the last 0x3444, to show unsaved changes and which blocks differ.
  `toneDetails[channel]` stays the edited copy; a re-query of 0x3444 must not overwrite it
  while there are unsaved edits (it would put back the saved values).
- `discardEdits(channel:)` (op 08) and `saveTone(as:channel:)`; refresh the library
  (GET 0x3440) after a save as.

## Phase 3: editor UI (`PresetEditor.swift`)
- **Its own page in the pager**, per guitar channel, so it can be reached by swiping
  like the other screens.
- **Opened from a tone button's long-press popover (iOS) or right-click menu (macOS)**
  with "Edit Tone…": jumps to the editor with that button's tone selected.
- **Reached by swiping**: no tone is chosen yet; the page asks to select one first.
- **Changing the tone inside the editor**: a tone picker listing every tone in the library
  (by category, like the existing tone picker), not only the four buttons.
- Selecting a tone in the editor plays it on the channel (0x3442), since 0x3445 edits
  apply to the tone the channel is playing and you should hear what you edit.
- Landscape layout:
  - header: tone name (tap to change tone) with an "edited" dot, *Save as…*, *Save*;
  - chain strip: the 8 slots in a row joined by a signal line, JBL order; bypassed slots
    dimmed, on ones amber; tap to select, a power control to bypass;
  - detail panel: model chips (scrolling for FX's 9) and large knobs (vertical drag,
    value with unit, double-tap for default). Knob is a new component in `Pads.swift`.
- Changing tone or leaving with unsaved edits asks: Save / Save as new… / Discard / Keep editing.
- Save as asks for a name, then offers to put the new tone on a button.

## Phase 4: wrap-up
README section, protocol notes, check on the iPhone and the Mac.

## Decisions
- Factory tones can be overwritten, as in the JBL app (capture 4 saved Brit Crunch into itself).
- The editor edits one guitar channel: the channel of the tones page it was opened from,
  or a channel picker when reached by swiping with both guitars plugged in.
