# JBL BandBox Trio — BLE protocol notes

## Transport
- BLE GATT. The device advertises with no name and no manufacturer data; the name
  "JBL BandBox Trio" only shows after connecting. It rotates its BLE address every few
  minutes, so the CoreBluetooth identifier changes (seen: D4224BE5…, 4414F98A…, B8C2064A…).
  `BLEScan.app --args auto listen <secs> com` finds it by probing nearby silent devices
  for the excelpoint com service.
- Only one control client at a time: an iPhone with the JBL app connected gets us kicked.
- Services:
  - `65786365-6C70-6F69-6E74-2E636F6D0000` ("excelpoint.com"): **command channel**
    - `…636F6D0002` write / writeNoResp (host → speaker)
    - `…636F6D0001` notify (speaker → host); reading is not permitted
  - `65786365-6C70-6F69-6E74-2E636E6C0000` ("excelpoint.cnl"): same layout.
    **Subscribing to its notify characteristic gets us disconnected within ~100 ms**, so leave it alone.
  - `FE2C` with `FE2C1234…123A`: Google Fast Pair; ignore.

## Message framing (confirmed from the JBL app capture)
All messages, both directions, little-endian:
```
00 dd | TT TT | FT FI | LL LL | payload (LL bytes)
magic   type    frag    length
```
| Type | Direction | Payload |
|---|---|---|
| 1 GET | host → speaker | list of u16 property IDs |
| 1 GET reply | speaker → host | `00 00` status + property records |
| 2 SET | host → speaker | property records |
| 2 SET reply | speaker → host | `00 00` status (OK) |
| 3 EVENT | speaker → host | `00 00` status + property records (unsolicited) |
| 4 ACK | host → speaker | `02 00 00 00`, sent by the app after each EVENT. Not required: our listener never ACKed and stayed connected. |

`FT FI` = fragment total / fragment index. `01 00` for a normal message. Big replies are split: `02 00` then `02 01`. Concatenate the payloads.

A **property record** is `ID ID | VL VL | value…` (ID and value-length u16 LE).
The app writes to `…636F6D0002` with Write Request (handle 0x03ea on the phone) and
gets notifications on `…636F6D0001` (handle 0x03ec).

Some SETs are really parameterised queries: `SET 0x3405=(a,b)…` makes the speaker
send `EVENT 0x3406=(a,b,value)…`; `SET 0x3400=n…` → `EVENT 0x3401=(n,…)`.

### Example: turn the tuner on
```
00 dd 02 00 01 00 05 00 | 00 31 01 00 01      SET 0x3100 = 01
00 dd 02 00 01 00 06 00 | 04 38 02 00 01 02   SET 0x3804 = 01 02   (the app sends this right after)
```
To turn it off the app sends `SET 0x3804 = 01 00`, then `SET 0x3100 = 00`.

## Properties
| ID | Len | Example | Meaning | Source |
|---|---|---|---|---|
| 0x0001 | 2 | `00 01` | Hello EVENT on subscribe (protocol version?) | listen |
| 0x0002 | 0 | | Keep-alive EVENT every 5 s | app capture |
| 0x0004 | 2 | `11 21` | Firmware version | app capture |
| 0x0006 | 16 | "JBL BandBox Trio" | Model name (ASCII) | app capture |
| 0x0008 | 16 | ASCII | Serial number | app capture |
| 0x000d | 1 | `64` (100) | **Battery %** | listen + app capture |
| 0x0031 | 16 | sec,min,hour,?,day,month,year(u16),?,"+03:00",dst | Date/time; the app SETs it on connect | app capture |
| 0x3100 | 1 | `00`/`01` | **Tuner off/on**. GET works too. **Verified from the Mac**: SET → OK reply + EVENT confirming the new state A tuner turned on with SET **switches itself off after ~11 s**; repeating SET 0x3100 = 01 every 5 s keeps it on (tested 36 s). Turned on from the speaker's button, it stayed on | app capture + Mac test |
| 0x3101, 0x3102, 0x3104, 0x3107 | 1 | `00` | Tuner readings? All 0 when nothing was played | app capture |
| 0x3103 | 2 | `30 11` | **Tuner reference pitch** ×10: 0x1130 = 4400 → 440.0 Hz. GET from the Mac works | app capture + Mac test |
| 0x3106 | 10 | `36 3b a5 42 06 87 2a 0c 40 01` | **Live tuner feed**, EVENT ~10×/s while the tuner is on. Bytes 0–3: detected frequency, float32 Hz (82.6). Byte 4: **guitar string** it's matched to, 1 = high E … 6 = low E (a string tuner, not chromatic). Bytes 5–8: offset from that string's target, float32 in **half-cents** (×2 for cents; checked at 82.6, 80.1 and 102.5 Hz). Byte 9: 1 = signal, 0 = silence (then all bytes 0) | `captures/speaker-controls.listen.log` |
| 0x3804 | 2 | `01 02` / `01 00` | Sent with the tuner on/off (UI mode/page?) | app capture |
| 0x3441 | 1 | `03` | **Query current tone**: SET 0x3441 = 03 → EVENT 0x3442 with the current tone | Mac probe |
| 0x3442 | 2 | `03 NN` | **Current tone**: NN = tone ID from the 0x3440 library (not a 1–3 slot; the speaker's preset buttons step through the library). SET selects a tone. GET returns nothing; use 0x3441. The leading `03` is always 03 (input channel?) | listen + app capture 2 + Mac test |
| 0x3443 | 1 | `NN` | **Query tone details**: SET 0x3443 = NN → EVENT 0x3444. The app sends it after every tone change | app capture 2 |
| 0x3444 | ~160 | `NN cat len name… cnt blocks…` | **Tone details**: ID, category, name length, name, then `cnt` (8) **effect blocks**, each `slot u8 · model u16 · bypass u8 · k u8 · k × (param u8, float32)`. bypass 1 = off, 0 = on. Slots: 0 gate?, **1 compressor, 2 distortion**, 3 amp (5 params), 4 cab (no params), **5 FX, 6 delay, 7 reverb**. Example Brit Crunch: delay params (1, 450.0)=time ms? | app capture 2 + 3 |
| 0x3445 | var | `03 NN op slot …` | **Edit one effect block** of tone NN (on channel 03). The edit lasts until the tone changes; 0x3446 op 04 saves it. **op 01 = replace the block**: `03 NN 01 slot model bypass k params…`, the slot's whole block from 0x3444 with the new bypass byte; to toggle a pedal, copy the block and flip bypass. Speaker replies EVENT `03 NN 01 slot ff ff bypass 00`. **op 02 = change model**: `03 NN 02 slot model(u16) ff 00` (ff = leave bypass alone); speaker replies EVENT op 00 `03 NN 00 slot model ff k params…`, the new model with its default parameters. See *Effect models* below | app capture 3 + 4 |
| 0x3446 | 6 | `03 op NN target ff 00` | **Tone action**. **op 04 = save** tone NN's pedal and model edits into the tone, target ff = into itself; the echo fills the target (`03 04 0f 0f ff 00`), then the app re-queries 0x3443. A target other than NN is probably *save as* (user tones 0x33, 0x34); not captured. **op 08**: sent when leaving the pedal page after unsaved edits in capture 3, echoed unchanged and followed by EVENT 0x3442 with the same tone: probably *discard edits* (reload the saved tone) | app capture 3 + 4 |
| 0x3448 / 0x3449 | 1 / 6 | `03` / `03 04 01 09 0e 16` | SET 0x3448 = 03 → EVENT 0x3449: `03`, count 4, then 4 tone IDs. Probably the tones on the speaker's preset buttons | app capture 3 |
| 0x3406 | 3 | `a b VV` | **Level table** (the app SETs `a b VV` + 7 zero bytes; 3 bytes also work), keyed by (a,b). VV is **0–32** (32 knob clicks, verified end to end). `(00 00)` = **master volume**; SET 0x3406 = 00 00 VV sets it. Otherwise the key is **(channel, input type)** from 0x3401, so each channel keeps one volume per input type: (01 01) ch 1 mic (its Volume knob, 0–32), (01 02) ch 1 guitar, (02 01) ch 2 mic, (02 03) ch 2 line, (03 02) ch 3 guitar. Plugging a jack in sends an EVENT with that input's volume. The speaker sends an EVENT on every knob click. (04 04)=24 is something else (see 0x2d42) | `captures/speaker-controls.listen.log`, `captures/inputs.decoded.txt` |
| 0x2d42 | 1 | `07` | **Channel 4 volume** (USB / Bluetooth audio; channel 4 has no input jack). Not in the 0x3406 table: EVENT on every knob click with channel 4 selected, GET and SET from the Mac work (7→8→7). Range 0–32 like the other channels (32 confirmed as the speaker's maximum). (04 04) in 0x3406 is something else: SETs to it are accepted but don't change channel 4 | Mac app log 2026-10-17 |
| 0x3405 | 2 | `a b` | SET to query entries of 0x3406 | app capture |
| 0x3400 / 0x3401 | 1 / 3 | `n` / `n j t` | Channel query / **input state** of channel n (1–3). SET 0x3400 = n → EVENT 0x3401. **j = 1 jack plugged in, 0 empty. t = input type: 01 mic, 02 guitar, 03 line**, set by the channel's switch (ch 1: mic/guitar, ch 2: mic/line; ch 3 is always guitar). The speaker sends an EVENT on every plug, unplug and switch move, with or without a jack. Channel n's volume is level (n, t). Earlier read as a channel-selection event | `captures/inputs.decoded.txt` |
| 0x3402 / 0x3403 | 1 / 2 | `03` / `03 TT` | **Pickup type** of a guitar input, per channel: SET 0x3402 = 03 → EVENT 0x3403 = 03 TT; SET 0x3403 = 03 TT selects it, echoed as an EVENT. Channel 1 has its own (01 00 seen, switch on mic, nothing plugged); 0x3402 = 02 gets no answer (channel 2 has no guitar input). Stagehand handles only channel 3. TT **00 = Single coil, 01 = Active, 02 = Passive humbucker** (checked against the JBL app with Stagehand showing the speaker's setting) | app capture 5 |
| 0x31c3 | 14 | `ch 01 bass mid treble` | **Mic EQ** of channel ch (1–2): three float32s in dB, **−12…+12** in 1 dB steps, from the channel's Bass and Treble knobs (there is no Mid knob; mid stayed −5.0). The speaker sends an EVENT on every knob click and when a mic is plugged in or the switch moves. Channel 2 read 0, 0, 0 dB, also with a mic plugged in (knobs centred?). GET returns nothing, and SET 0x31c2 = ch is accepted but sends no event; no way found to read it on connect. Byte 1 is always 01 | `captures/mic-controls.decoded.txt`, `captures/probe-mic-eq.log` |
| 0x0c09 | 1 | `00`…`0c` | **Mic delay**, channel 1's Delay knob: 0–12, EVENT on every click. GET works. Whether channel 2's knob uses the same property is untested | `captures/mic-controls.decoded.txt`, `captures/probe-mic-eq.log` |
| 0x0c0a | 1 | `00`…`0c` | **Mic reverb**, channel 1's Reverb knob: 0–12, like 0x0c09 | same |
| 0x0c0c, 0x0c10 | 4 | `9a 99 19 40` / `00 00 00 00` | float32 2.4 and 0. Sent with a channel 1 switch change; unknown. GET works | `captures/inputs.decoded.txt` |
| 0x3085 | 1 | `00`/`01` | **STEM AI off/on**. **SET and GET from the Mac work** | listen + Mac test |
| 0x3080 | 1 | `00`/`01` | **STEM AI karaoke mode** off/on (STEM AI already on). On: the speaker sets stem 1 = vocals, stem 2 = off and stem 2's volume (0x3082) to 0, leaving only vocals and Others. Off: stem 1 = guitar, stem 2 = vocals, stem 2 volume back to 32 | app capture 4 |
| 0x30c1 | 1 | `fd`…`03` | **Pitch shift** (probably): signed semitones, ff = −1. The app SETs then GETs it; the speaker EVENTs 0x30c1 + 0x30c0. Seen −3…+3 (the app may allow ±5). Read once on connect. Not pickup type: that's 0x3403 | app capture 4 |
| 0x30c0 | 1 | `00`/`01` | 1 while 0x30c1 is not 0 (pitch shift active?); EVENT only | app capture 4 |
| 0x3081 | 2 | `ch type` | **STEM channel type**, ch 1–2: 0 off, 1 guitar, 2 vocals, 3 drums. SET selects it. A type can be on only one channel: the app first sets the other channel to a different type or off. EVENT 0x3085 + 0x3080 + both 0x3081 follows each change | app capture 3 |
| 0x3082 | 2 | `ch VV` | **STEM channel volume**, ch 1, 2, 3 (3 = Others), VV 0–32. The app SETs `ch VV` + 7 zero bytes. Turning STEM AI off resets all three to 32 | app capture 3 |
| 0x3083 / 0x3084 | 1 | `ch` | SET to query: 0x3083 = ch → EVENT 0x3081; 0x3084 = ch → EVENT 0x3082 | app capture 3 |
| 0x3080, 0x3081, 0x3082 | | | Sent alongside STEM AI changes | listen |
| 0x3440 | 432 | records `id cat len name…` | **Tone preset library**: 27 factory tones (Clean Comping … Bypassed) + user tones at 0x33, 0x34. GET works; reply comes in 2 fragments | Mac probe |
| 0x344a | | records `cat len name…` | **Tone categories**: Pop, Funk, Blues, Rock, Metal, Acoustic, Bass, Others | Mac probe |
| 0x3805 | 10 | `01 02 03 04 05 06 09 0a 0b 0d` | Capability/feature list? | app capture |
| 0x1008, 0x000c, 0x2c00–0x2c05, 0x30c1, 0x3000, 0x3040, 0x3145, 0x3148, 0x0ba1, 0x3404, 0x3407 | | | Read once on connect; unknown | app capture |

## Effect models
The model in a 0x3444 block is a u16. For the pedals it's one ID space; the amp (slot 3) and
cab (slot 4) use the low byte for the type (06 amp, 08 cab) and the high byte for the variant.
The JBL app's model lists (app capture 4, changing models on Brit Crunch):

| Slot | Pedal | Model IDs | Notes |
|---|---|---|---|
| 0 | gate? | 00 | always off in factory tones |
| 1 | Compressor | 01 | one model |
| 2 | Distortion | 02 Auto-Wah, 03 Touch-Wah, 04 Precision Drive | Wahs and the drive share this slot. 04 = Precision Drive for sure (Soulful Verb's 40/25/36 = Drive, Bright, Level); 02 vs 03 from tap order only |
| 3 | Amp | 0x0006, 0x0106, 0x0206, 0x0306, 0x0506 seen | not switched yet |
| 4 | Cab | 0x0008, 0x0208, 0x0308, 0x0608, 0x0b08 seen | not switched yet |
| 5 | FX | 0e Echo Phase, 0f Green Phaser, 11 Notch Phaser, 12 Minivibe, 13 Tremolo, 0b Chorus, 0c Retro Shiver, 0d Jetter Flanger, 09 Grand Vibrato | App order. 9 models; 0a and 10 not offered. Matched by tap order and knob count; Echo Phase's one knob = Speed |
| 6 | Delay | 14 Pure Echo, 15 Analog Echo, 16 Echopress 900, 17 Sweep Echo, 18 Sweet Echo | Pure Echo params: 1 Time (ms), 2 Fdbk, 0 Mix |
| 7 | Reverb | 1b | one model |

The names come from the JBL app's pedal pages (screenshots, 2026-10-17); the speaker sends only IDs.
Each parameter is `(param id u8, float32)`; parameter IDs are per model, not per slot.
The ranges aren't mapped yet; known values look like 0–100 knobs, and delay param 1 is the time in ms (180–820 seen).

## Not mapped yet
Things in the JBL app that haven't been captured. `capture-app-features.sh <area>` has prompts for each:
- **Pitch shifter**: probably 0x30c1 (above); confirm and check the ±5 ends.
- **Pedal parameters** (gain, delay time…): the change is probably 0x3445 op 01 with new param floats; not captured.
- **Amp and cab models**.
- **Drum machine**, **looper**, **global EQ**, **channel 4 EQ**.
- **Save as** a new user tone (0x3446 with another target?).

## Still unknown
- ~~SET commands for preset and STEM AI~~ **Verified from the Mac** (`captures/preset-stem-test-1.log`).
- ~~How to read the current preset on connect~~ **SET 0x3441 = 03** (verified).
- ~~What the `03` in 0x3441/0x3442 means~~ **The channel**: SET 0x3441 = 01 → EVENT 0x3442 = 01 1b, so channel 1 has its own tone (0x1b) as well; 01 for channel 2 gets no answer. Untested: selecting channel 1's tone, and whether 0x3444/0x3445 edits work on it.
- The parameter layout inside 0x3444 (gain, EQ, effects…?).
- ~~Live tuner readings~~ All in 0x3106 (decoded 2026-10-17); 0x3101/02/04/07 stayed 0.
- ~~Channel 1's level key~~ (channel, input type), see 0x3401 (`captures/inputs.decoded.txt`).
- The app shows no percentages either; approximate 50% gave 16 and 100% gave 32, so percent = raw / 32.
- Slot 0. ~~Whether 0x3445 edits are saved into the tone~~: not until SET 0x3446 = 03 04 NN ff ff 00 (app capture 4).
- 0x3446 op 08 (discard edits?).
- ~~Whether SET works from the Mac without the app's connect sequence~~ **It does** (2026-10-16 20:39, `captures/tuner-test-1.log`): no datetime/handshake needed, no ACKs needed.

## Logs
- `captures/mic-controls.listen.log` (+ `.timeline.log`, `.markers.log`, `.decoded.txt`): mic in channel 1, its Delay, Reverb, Bass, Treble and Volume knobs each swept up then down (16:47–16:51, 2026-10-18). The two Mid prompts did nothing: there is no Mid knob. Script: `capture-mic-controls.sh`
- `captures/probe-mic-eq.log`: SET 0x31c2 = 01/02, GET 0x0c09/0x0c0a/0x0c0c/0x0c10 and GET 0x31c3 from the Mac (16:52, 2026-10-18)
- `captures/inputs.listen.log` (+ `.timeline.log`, `.markers.log`, `.decoded.txt`): mic, guitar and line-in plugged into channels 1–3 in turn, switches flipped, polling 0x3400/0x3402/0x3441 per channel every 3 s (16:35–16:40, 2026-10-18). At the start channel 1's switch was on mic and channel 2's on line, so "set channel 2 to line in" sent nothing. Script: `capture-inputs.sh`
- `captures/app-capture-5-pickup.pklg` (+ `.decoded.txt`): JBL app opening the pickup page (on Passive humbucker) and choosing Single coil, 14:11, 2026-10-17
- `captures/app-capture-4-features.pklg` (+ `.decoded.txt`): JBL app, 13:41–13:50, 2026-10-17, no spoken prompts: karaoke on/off, pitch shift (0x30c1) −3…+3, Brit Crunch's distortion, FX and delay models, then saving the tone (13:50:17)
- `captures/app-capture-3-controls.pklg` (+ `.decoded.txt`), prompts in `captures/app-controls.markers.log`: JBL app toggling each pedal, master and ch 3 volume, STEM AI types and volumes (10:49–10:56, 2026-10-17). Script: `capture-app-controls.sh`
- `captures/speaker-controls.listen.log` (+ `.timeline.log`, `.decoded.txt`): speaker knobs swept master and ch 3 volume 0→32, channel select, tuner on low E (in tune, flat), A and high E (10:39–10:45, 2026-10-17). Script: `capture-speaker-controls.sh`
- `captures/app-capture-2-presets.pklg` (+ `.decoded.txt`): JBL app stepping tones 1 → 9, 20:53, 2026-10-16
- `captures/probe-current-preset3.log`: SET 0x3441 = 03 returns the current tone
- `captures/preset-stem-test-1.log`: Mac sets preset 2→1 and STEM AI on→off (20:40, 2026-10-16). Decode with `python3 -I decode-log.py <log>`
- `captures/tuner-test-1.log`: Mac sends GET tuner_ref, tuner on, tuner off (20:39, 2026-10-16)
- `captures/app-capture-1.pklg` (+ `.decoded.txt`): JBL app on iPhone, 20:06–20:07, 2026-10-16: connect sequence + tuner on/off
- `captures/guided1.timeline.log`: spoken-prompt session 20:30–20:32, 2026-10-16 (tuner, volume, STEM AI)
- `captures/listen-buttons.log`: button session 20:22–20:25, 2026-10-16
- `captures/listen-run4-com-only.log`: first stable com-only connection
- `captures/listen-run2.log`: disconnect loop when also subscribing to cnl
