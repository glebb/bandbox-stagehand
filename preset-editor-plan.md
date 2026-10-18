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
| Parameter names, ranges and units per model | All mapped (protocol-notes.md, *Effect models*) |
| Amp models and names | Mapped: 11 amps, op 03 between guitar amps, op 02 for Acoustic / Studio Bass |
| Cab models and names | Mapped: 12 cabs, op 03, no params |
| Gate (slot 0) | Mapped: Noise Gate (00), Gate (1c) |
| Save as, rename, delete, reset | Mapped: 0x3446 op 09 / 03 / 07 / 02 |
| Discard edits (0x3446 op 08) | Heard from the Mac |

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
**Phase 0 is done** (2026-10-18): every slot's models, knob names and ranges, and the tone
actions (save, save as, rename, delete, reset, discard) are in protocol-notes.md.

## Phase 1: model layer (`Protocol.swift`, `Effects.swift`) — done
- `EffectBlock.params` becomes `[EffectParam]` (`id u8`, `value Float`); `bytes` builds from them.
- `EffectSlot` covers all 8 slots (gate, comp, dist, amp, cab, FX, delay, reverb) with their
  models; `Pedal` stays as the tones screen's quick-switch subset.
- `EffectCatalog`: model → `[ParamSpec]` (name, range, unit, step, format). A parameter
  missing from it shows as a generic knob over its raw value, so the editor works before
  the research is complete.

## Phase 2: client (`BandBoxClient.swift`) — done
Checked offline against the captures (builders, round trip of every captured tone, catalog
IDs); not yet against the speaker, which needs the editor UI.

- `setParam(slot:param:value:channel:)`: optimistic update + op 04 with that one param; while a knob is
  dragged, coalesce writes (latest value, about every 50 ms).
- `setPedal` / `setModel` for every slot.
- `savedDetails[channel]`, the last 0x3444, to show unsaved changes and which blocks differ.
  `toneDetails[channel]` stays the edited copy; a re-query of 0x3444 must not overwrite it
  while there are unsaved edits (it would put back the saved values).
- `discardEdits(channel:)` (op 08); `saveToneAs(name:category:channel:)` (op 09; the echo
  gives the new ID); `renameTone` (op 03), `deleteTone` (op 07, user tones), `resetTone`
  (op 02, back to factory). Refresh the library (GET 0x3440) after save as, rename and delete.

## Phase 3: editor UI (`PresetEditor.swift`) — done
Tried on the Mac with the speaker (2026-10-18): knobs, models, bypass and save as work.
Tried on the iPhone too; its popovers needed a flexible height to scroll to their last row.

- **Its own page in the pager**, the last one (after the tones pages, mix and STEM AI),
  so it can be reached by swiping like the other screens.
- **Opened from a tone button's long-press popover (iOS) or right-click menu (macOS)**
  with "Edit Tone…": jumps to the editor with that button's tone selected.
- **Reached by swiping**: opens on the tone the channel plays; the tone name's drop-down
  changes it. (A first version asked for a tone first; dropped after trying it, 2026-10-18.)
- **Changing the tone inside the editor**: a tone picker listing every tone in the library
  (by category, like the existing tone picker), not only the four buttons.
- Selecting a tone in the editor plays it on the channel (0x3442), since 0x3445 edits
  apply to the tone the channel is playing and you should hear what you edit.
- Landscape layout:
  - header: tone name (tap to change tone) with an "edited" dot, *Save as…*, *Save*;
  - chain strip: the 8 slots in a row joined by a signal line, JBL order; bypassed slots
    dimmed, on ones amber; tap to select, a power control to bypass;
  - detail panel: model chips (scrolling for FX's 9) and large knobs (vertical drag,
    value with unit). Knob is a new component in `Pads.swift`. No double-tap for the
    default yet: the catalog has no defaults (the op 02 replies carry them).
- Changing tone in the editor with unsaved edits asks: Save / Save as new… / Discard / Keep
  editing. Leaving the page doesn't: the edits stay on the speaker until the tone changes.
- Save as asks for a name (prefilled with the tone's) and a category (the 8 from 0x344a),
  then offers the channel's four tone buttons (or none) for the new tone. Save as keeps the source tone unchanged.
- The editor's tone menu: Rename and Delete for user tones, Reset to factory for factory tones.

## Phase 4: wrap-up — done
README section, protocol notes, check on the iPhone and the Mac.

## Decisions
- Factory tones can be overwritten, as in the JBL app (capture 4 saved Brit Crunch into itself).
- The editor edits one guitar channel: the channel of the tones page it was opened from,
  or the primary guitar channel when reached by swiping; with both guitars plugged in, a
  CH 1 / CH 3 picker in the editor's header switches.
