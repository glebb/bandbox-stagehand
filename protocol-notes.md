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
| 0x3100 | 1 | `00`/`01` | **Tuner off/on**. GET works too. **Verified from the Mac**: SET → OK reply + EVENT confirming the new state A tuner turned on with SET **switches itself off after ~11 s**; repeating SET 0x3100 = 01 every 5 s keeps it on (tested 36 s). Turned on from the speaker's button, it stayed on. Selecting a channel on the speaker, or plugging or unplugging a jack, **turns it off** (EVENT 0x3100 = 00); the next keep-alive SET turns it back on | app capture + Mac test, `captures/tuner.decoded.txt` |
| 0x3101, 0x3102, 0x3104, 0x3107 | 1 | `00` | Tuner readings? All 0 when nothing was played | app capture |
| 0x3103 | 2 | `30 11` | **Tuner reference pitch** ×10: 0x1130 = 4400 → 440.0 Hz. GET from the Mac works | app capture + Mac test |
| 0x3106 | 10 | `36 3b a5 42 06 87 2a 0c 40 01` | **Live tuner feed**, EVENT ~10×/s while the tuner is on. Bytes 0–3: detected frequency, float32 Hz (82.6). Byte 4: **guitar string** it's matched to, 1 = high E … 6 = low E (a string tuner, not chromatic). Bytes 5–8: offset from that string's target, float32 in **half-cents** (×2 for cents; checked at 82.6, 80.1 and 102.5 Hz). Byte 9: 1 = signal, 0 = silence (then all bytes 0). **No channel byte: it hears a guitar in channel 1 or channel 3**, whichever channel is selected on the speaker (with one guitar; two at once untested) | `captures/speaker-controls.listen.log`, `captures/tuner.decoded.txt` |
| 0x3804 | 2 | `01 02` / `01 00` | Sent with the tuner on/off (UI mode/page?) | app capture |
| 0x3441 | 1 | `03` | **Query current tone**: SET 0x3441 = 03 → EVENT 0x3442 with the current tone | Mac probe |
| 0x3442 | 2 | `ch NN` | **Current tone** of guitar channel ch (01 or 03, each has its own): SET 0x3442 = 01 NN switched channel 1 audibly and left channel 3 alone (`captures/ch1-guitar.decoded.txt`). The speaker also sends it unprompted for channel 01 (01 33 when its preset button was pressed), so a client must check the channel byte. NN = tone ID from the 0x3440 library (not a 1–3 slot; the speaker's preset buttons step through the library). SET selects a tone. GET returns nothing; use 0x3441. The leading byte is the channel | listen + app capture 2 + Mac test |
| 0x3443 | 1 | `NN` | **Query tone details**: SET 0x3443 = NN → EVENT 0x3444. The app sends it after every tone change | app capture 2 |
| 0x3444 | ~160 | `NN cat len name… cnt blocks…` | **Tone details**: ID, category, name length, name, then `cnt` (8) **effect blocks**, each `slot u8 · model u16 · bypass u8 · k u8 · k × (param u8, float32)`. bypass 1 = off, 0 = on. Slots: 0 gate?, **1 compressor, 2 distortion**, 3 amp (5 params), 4 cab (no params), **5 FX, 6 delay, 7 reverb**. Example Brit Crunch: delay params (1, 450.0)=time ms? | app capture 2 + 3 |
| 0x3445 | var | `ch NN op slot …` | **Edit one effect block** of tone NN on channel ch (01 works too: channel 1's delay went on and off audibly, echoed as `01 1b 01 06 ff ff 00 00`; an edit to a tone that is no longer current is still accepted and echoed). The edit lasts until the tone changes; 0x3446 op 04 saves it. **op 01 = replace the block**: `03 NN 01 slot model bypass k params…`, the slot's whole block from 0x3444 with the new bypass byte; to toggle a pedal, copy the block and flip bypass. **op 01 does not change parameter values**: a block with new floats is accepted and echoed like a bypass change, but nothing changes in the sound (delay time 250 → 800 → 100 ms, amp knob 0 → 100 → 0 on channel 1 with a guitar playing, 18:00, 2026-10-18; that run's log was overwritten by the op 04 run). op 01 applies only the bypass byte. **op 04 = set one parameter**: `ch NN 04 slot model(u16) ff 01 param f32`, a block with bypass ff (unchanged) and one param; the speaker echoes it unchanged. While a knob is dragged the JBL app sends one every 60–120 ms (`captures/app-capture-6-delay.decoded.txt`). **Verified from the Mac by ear**: delay mix, time and feedback and amp param 0 (0 and 100) all changed the sound on channel 1, one SET per param (`captures/preset-edit-listen.*`). **0x3444 does not show unsaved edits**: queried right after the edit it still has the saved values, so a client has to keep its own copy of the edited blocks. Speaker replies EVENT `03 NN 01 slot ff ff bypass 00`. **op 03 = change amp or cab model** (slot 3 guitar amps, slot 4 cabs): `ch NN 03 slot model(u16) ff 00`, answered like op 02 with the new model and its defaults (a cab: no params); the JBL app uses it between the 0xNN06 amps and the 0xNN08 cabs, and op 02 for Acoustic Amp (0x001d) and Studio Bass (0x001e). Going back from those two to a 0xNN06 amp is not captured (`captures/app-capture-6-amp.decoded.txt`). **op 02 = change model**: `03 NN 02 slot model(u16) ff 00` (ff = leave bypass alone); speaker replies EVENT op 00 `03 NN 00 slot model ff k params…`, the new model with its default parameters. See *Effect models* below | app capture 3 + 4 |
| 0x3446 | var | `ch op NN target cat len name…` | **Tone action** on tone NN for guitar channel ch; unused fields are ff (cat) and 00 (len). See *Tone actions* | app capture 3 + 4, `captures/app-capture-6-save.*`, Mac probe |
| 0x3448 / 0x3449 | 1 / 6 | `03` / `03 04 01 09 0e 16` | SET 0x3448 = 03 → EVENT 0x3449: `03`, count 4, then 4 tone IDs. Probably the tones on the speaker's preset buttons | app capture 3 |
| 0x3406 | 3 | `a b VV` | **Level table** (the app SETs `a b VV` + 7 zero bytes; 3 bytes also work), keyed by (a,b). VV is **0–32** (32 knob clicks, verified end to end). `(00 00)` = **master volume**; SET 0x3406 = 00 00 VV sets it. Otherwise the key is **(channel, input type)** from 0x3401, so each channel keeps one volume per input type: (01 01) ch 1 mic (its Volume knob, 0–32), (01 02) ch 1 guitar, (02 01) ch 2 mic, (02 03) ch 2 line, (03 02) ch 3 guitar. Plugging a jack in sends an EVENT with that input's volume. The speaker sends an EVENT on every knob click. (04 04)=24 is something else (see 0x2d42) | `captures/speaker-controls.listen.log`, `captures/inputs.decoded.txt` |
| 0x2d42 | 1 | `07` | **Channel 4 volume** (USB / Bluetooth audio; channel 4 has no input jack). Not in the 0x3406 table: EVENT on every knob click with channel 4 selected, GET and SET from the Mac work (7→8→7). Range 0–32 like the other channels (32 confirmed as the speaker's maximum). (04 04) in 0x3406 is something else: SETs to it are accepted but don't change channel 4 | Mac app log 2026-10-17 |
| 0x3405 | 2 | `a b` | SET to query entries of 0x3406 | app capture |
| 0x3400 / 0x3401 | 1 / 3 | `n` / `n j t` | Channel query / **input state** of channel n (1–3). SET 0x3400 = n → EVENT 0x3401. **j = 1 jack plugged in, 0 empty. t = input type: 01 mic, 02 guitar, 03 line**, set by the channel's switch (ch 1: mic/guitar, ch 2: mic/line; ch 3 is always guitar). The speaker sends an EVENT on every plug, unplug and switch move, with or without a jack. Channel n's volume is level (n, t). Earlier read as a channel-selection event | `captures/inputs.decoded.txt` |
| 0x3402 / 0x3403 | 1 / 2 | `03` / `03 TT` | **Pickup type** of a guitar input, per channel: SET 0x3402 = 03 → EVENT 0x3403 = 03 TT; SET 0x3403 = 03 TT selects it, echoed as an EVENT. Channel 1 has its own: SET 0x3403 = 01 TT from the Mac works and is echoed (Stagehand log, 2026-10-18). 0x3402 = 02 gets no answer (channel 2 has no guitar input). TT **00 = Single coil, 01 = Active, 02 = Passive humbucker** (checked against the JBL app with Stagehand showing the speaker's setting) | app capture 5 |
| 0x31c3 | 14 | `ch t bass mid treble` | **Mic / line EQ** of channel ch (1–2) for input type t (01 mic, 03 line, as in 0x3401): three float32s in dB, **−12…+12** in 1 dB steps, from the channel's Bass, Mid and Treble knobs. Each (channel, input type) keeps its own EQ: channel 2's mic kept bass +12 while the line input was used and changed. Mic inputs have no Mid knob; mid stays where it was (ch 1 −5, ch 2 0). The speaker sends an EVENT on every knob click and when a jack goes in or the switch moves (once, plugging in the line cable, it sent the mic's EQ). GET returns nothing, and SET 0x31c2 = ch is accepted but sends no event; no way found to read it on connect | `captures/mic-controls.decoded.txt`, `captures/ch2-controls.decoded.txt`, `captures/probe-mic-eq.log` |
| 0x0c09 / 0x0c0d | 1 | `00`…`0c` | **Mic delay** of channel 1 / channel 2 (the Delay knob with the switch on mic): 0–12, EVENT on every click. GET works | `captures/mic-controls.decoded.txt`, `captures/ch2-controls.decoded.txt` |
| 0x0c0a / 0x0c0e | 1 | `00`…`0c` | **Mic reverb** of channel 1 / channel 2: 0–12, like delay | same |
| 0x0c0c / 0x0c10 | 4 | `9a 99 19 40` / `00 00 00 00` | Channel 1 / channel 2, float32 2.4 and 0; unknown. GET works. A GET of 0x0c00–0x0c17 answers only 0x0c09–0x0c0e and 0x0c10: four properties per channel with 0x0c0b / 0x0c0f empty | `captures/probe-mic-block.log` |
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

## Tone actions (0x3446)
`ch op NN target cat len name…`, echoed by the speaker as an EVENT (`captures/app-capture-6-save.*`, JBL app on channel 1, 19:18–19:22, 2026-10-18):

| op | Sent | Echo | Meaning |
|---|---|---|---|
| 02 | `01 02 0d ff ff 00` | same | **Reset to factory**: tone NN back to its factory settings; the app re-queries 0x3443 |
| 03 | `01 03 36 36 ff 05 "test3"` | `01 03 36 ff ff 05 "test3"` | **Rename** user tone NN (target = NN, cat ff = unchanged); the app re-reads the library (GET 0x3440) |
| 04 | `03 04 0f ff ff 00` | `03 04 0f 0f ff 00` | **Save** NN's edits into itself |
| 07 | `01 07 36 ff ff 00` | same | **Delete** user tone NN; the app re-reads the library and selects tone 01 on the channel |
| 08 | `01 08 0d ff ff 00` | same, then EVENT 0x3442 | **Discard** NN's edits (heard from the Mac) |
| 09 | `01 09 0d ff 00 05 "test1"` | `01 09 ff 35 00 05 "test1"` | **Save as** a new user tone: NN's current state *with its unsaved edits* (delay 1000 ms went into the new tone, Feathered Blues kept 250) under a new name and category (cat from 0x344a: 00 Pop … 07 Others). The echo gives the new ID as target (0x35, then 0x36: the next free ID after the user tones 0x33, 0x34). NN keeps its saved settings. The app then GETs 0x3440 and selects the new tone with 0x3442 |

The JBL app's *Save as* page (*Tallenna nimellä*) has a name field, prefilled with the tone's name, and the 8 categories as radio buttons; *Rename* (*Nimeä uudelleen*) only a name field. Names are plain ASCII as typed. The user-tone limit is not known.

## Effect models
The model in a 0x3444 block is a u16. For the pedals it's one ID space; the amp (slot 3) and
cab (slot 4) use the low byte for the type (06 amp, 08 cab) and the high byte for the variant.
The JBL app's model lists (app capture 4, changing models on Brit Crunch):

| Slot | Pedal | Model IDs | Notes |
|---|---|---|---|
| 0 | Gate | 00 Noise Gate, 1c Gate | Off in most factory tones, as 00. See *Gate, compressor and reverb parameters* |
| 1 | Compressor | 01 | one model. See *Gate, compressor and reverb parameters* |
| 2 | Distortion | 02 Auto-Wah, 03 Touch-Wah, 04 Precision Drive | Wahs and the drive share this slot. See *Distortion parameters* |
| 3 | Amp | 0xNN06 guitar amps, 0x001d, 0x001e | See *Amp models* |
| 4 | Cab | 0x0008 … 0x0b08 | See *Cab models* |
| 5 | FX | 0e Echo Phase, 0f Green Phaser, 11 Notch Phaser, 12 Minivibe, 13 Tremolo, 0b Chorus, 0c Retro Shiver, 0d Jetter Flanger, 09 Grand Vibrato | App order. 9 models; 0a and 10 not offered. See *FX parameters* |
| 6 | Delay | 14 Pure Echo, 15 Analog Echo, 16 Echopress 900, 17 Sweep Echo, 18 Sweet Echo | See *Delay parameters* |
| 7 | Reverb | 1b | one model. See *Gate, compressor and reverb parameters* |

### Amp models
In the JBL app's list order (`captures/app-capture-6-amp.*`, names and knob values from its amp pages; every screenshot's knobs equal the defaults in the speaker's op 00 reply). Params: **0 Drive, 1 Bass, 2 Mid, 3 Treble, 4 Volume**, all 0–100 (swept on Yellow Tweed). The app shows a category under the name.

| Model | Name | Category | Defaults (0–4) | Switched with |
|---|---|---|---|---|
| 0x0006 | American Clean | Clean | 32 55 27 79 59 | op 03 |
| 0x0106 | Jazz Sound | Clean | 54 73 40 63 66 | op 03 |
| 0x0206 | Yellow Tweed | Low Drive | 53 60 49 48 70 | op 03 |
| 0x0306 | UK Crunch | Drive | 65 64 45 65 62 | op 03 |
| 0x0406 | British Lead | Hi Gain | 100 94 40 60 55 | op 03 |
| 0x0506 | Vintage Drive | Drive | 66 43 50 77 43 | op 03 |
| 0x0606 | American Gain Stack | Hi Gain | 0 67 36 57 68 | op 03 |
| 0x0706 | US Metal | Hi Gain | 100 67 36 57 62 | op 03 |
| 0x0806 | Bass Amp | | 54 57 40 73 43 | op 03 |
| 0x001d | Acoustic Amp | | 0 75 39 55 85; param 0 is **Notch**, shown as "Off" at 0 (0–99 seen) | op 02 |
| 0x001e | Studio Bass | | – 68 28 74 83: no param 0 (Bass, Mid, Treble, Volume only) | op 02 |

Feathered Blues (0x0d) has 0x0506 with exactly Vintage Drive's defaults. Its JBL app preset page once showed Yellow Tweed (the screenshot that started the editor work), so that was probably after a switch to 0x0206, as the app sent at 18:24:09 in this capture.

### Cab models
In the JBL app's list order, switched with op 03 (`captures/app-capture-6-cab.*`; names from its cabinet pages, matched by screenshot time). Cabs have no params and no knobs in the app.

| Model | Name | | Model | Name |
|---|---|---|---|---|
| 0x0008 | Champion 1x8 | | 0x0608 | UK 1960 4x12 (Feathered Blues) |
| 0x0108 | Voks 2x12 | | 0x0708 | 6505 4x12 |
| 0x0208 | TR65 2x12 | | 0x0808 | Mebo 4x12 |
| 0x0308 | UK 2550 2x12 | | 0x0908 | M Bass 2x10 |
| 0x0408 | BM59 4x10 | | 0x0a08 | A Bass 8x10 |
| 0x0508 | Tanger 4x12 | | 0x0b08 | JC120 2x12 |

### FX parameters
Swept min → max in the JBL app (`captures/app-capture-6-fx.decoded.txt`), names from its pedal pages; each page's knobs equal the defaults in the speaker's op 02 reply. All 0–100 except Tremolo's Shape. Big knobs first, then the small ones, as on the page.

| Model | Name | Params (id Name default) |
|---|---|---|
| 0e | Echo Phase | 0 Speed 21 |
| 0f | Green Phaser | 0 Speed 36, 2 Fdbk 35; small: 1 Depth 100 |
| 11 | Notch Phaser | 0 Speed 24, 2 Fdbk 61; small: 1 Depth 39 |
| 12 | Minivibe | 0 Speed 75, 2 Fdbk 39; small: 1 Depth 18 |
| 13 | Tremolo | 1 **Shape 0–4**, a waveform picker drawn as icons, no names: 0 sine, 1 triangle, 2 square, 3 sawtooth, 4 rounded double-hump wave (`app-capture-6-dist`, end); 2 Speed 46; small: 3 Depth 100, 4 Bias 32. No param 0 |
| 0b | Chorus | 0 Speed 45, 4 Mix 36; small: 1 Depth 16 |
| 0c | Retro Shiver | 0 Speed 42, 1 Depth 31 |
| 0d | Jetter Flanger | 0 Speed 33, 1 Depth 53; small: 2 Offset 68, 3 Fdbk 66 |
| 09 | Grand Vibrato | 0 Speed 92, 1 Depth 36 |

### Distortion parameters
Swept in the JBL app (`captures/app-capture-6-dist.*`), names from its pedal pages, all 0–100. Four (three) small knobs in a row, in this order:

| Model | Name | Params (id Name default) |
|---|---|---|
| 02 | Auto-Wah | 1 Speed 18, 2 Freq 31, 4 Res 52, 0 Mix 79 (Feathered Blues' saved values) |
| 03 | Touch-Wah | 1 Sense 30, 3 Res 40, 0 Mix 100, 2 Freq 7 |
| 04 | Precision Drive | 0 Drive 44, 1 Bright 51, 2 Level 100 |

### Gate, compressor and reverb parameters
Swept in the JBL app (`captures/app-capture-6-{gate,comp,reverb}.*`), names from its pedal pages. All 0–100 except the ratio.

| Slot | Model | Name | Params (id Name default) |
|---|---|---|---|
| 0 | 1c | Gate | 0 Thresh 45, 1 Strength 62 (Feathered Blues) |
| 0 | 00 | Noise Gate (the app spells it "Nosie Gate") | 0 Thresh 30 |
| 1 | 01 | Compressor | 0 Thresh 84, 4 Output 18, 1 **Ratio 1.0–100.0** (the app sends and shows one decimal: 22.0), 2 Attack 41. Laid out 2 × 2 in that order |
| 7 | 1b | Reverb | 0 PreDelay 2, then 2 Decay 22, 4 Mix 24 |

The gate switches models with op 02 like the pedals; bypass of gate and compressor is op 01 as for the others.

### Delay parameters
The same for every delay model (`captures/app-capture-6-delay.*`, swept min → max in the JBL app, names from its pedal pages):

| Param | Name | Range | Models |
|---|---|---|---|
| 0 | Mix | 0–100 | all (Sweep Echo's not swept: the script prompted 3 of its 5 knobs; assumed the same) |
| 1 | Time | 20–1000 ms | all (Sweep Echo's assumed, as Mix). Tap tempo in the app sends the tapped time with a fraction (890.35); the speaker has no tap command |
| 2 | Fdbk | 0–100 | all |
| 3 | Speed | 0–100 | Sweep Echo |
| 4 | Depth | 0–100 | Sweep Echo |

The app sends whole numbers. Page layout: Fdbk, (Speed, Depth,) Mix in a row, Time as the big knob. Defaults (op 02 reply): Pure Echo 250 ms / 34 / 9, Analog Echo 438 / 32 / 39, Echopress 900 255 / 83 / 96, Sweep Echo 821 / 53 / 43 / 64 / 97, Sweet Echo 280 / 59 / 39 (time / fdbk / (speed / depth /) mix).

The names come from the JBL app's pedal pages (screenshots, 2026-10-17); the speaker sends only IDs.
Each parameter is `(param id u8, float32)`; parameter IDs are per model, not per slot.
The ranges aren't mapped yet; known values look like 0–100 knobs, and delay param 1 is the time in ms (180–820 seen).

## Not mapped yet
Things in the JBL app that haven't been captured. `capture-app-features.sh <area>` has prompts for each:
- **Pitch shifter**: probably 0x30c1 (above); confirm and check the ±5 ends.
- ~~Pedal parameters~~ Set with 0x3445 op 04; every slot's models and knobs are in *Effect models*.
- ~~Amp models~~ (see *Amp models*). ~~Cab models~~ (see *Cab models*).
- **Drum machine**, **looper**, **global EQ**, **channel 4 EQ**.
- ~~Save as, rename, delete~~ See *Tone actions*. Still open: how many user tones fit, and whether rename can change the category.

## Still unknown
- ~~SET commands for preset and STEM AI~~ **Verified from the Mac** (`captures/preset-stem-test-1.log`).
- ~~How to read the current preset on connect~~ **SET 0x3441 = 03** (verified).
- ~~What the `03` in 0x3441/0x3442 means~~ **The guitar channel** (01 or 03): each has its own tone, and 0x3442 and 0x3445 work for channel 01 (`captures/ch1-guitar.decoded.txt`). 01 for channel 2 gets no answer.
- ~~Whether the tuner listens to channel 1, 3 or the selected channel~~ Both inputs, not the selection (`captures/tuner.decoded.txt`). Untested: two guitars at once, and a mic or line input.
- The speaker's channel selection sends no message at all, so a client can't know which channel is selected.
- Which channel the speaker's preset button steps when both guitar inputs are in use: with the channel 1 switch on guitar it stepped channel 1 (0x1b → 0x33, confirmed by pressing it in `capture-ch1-guitar.sh`).
- The parameter layout inside 0x3444 (gain, EQ, effects…?).
- ~~Live tuner readings~~ All in 0x3106 (decoded 2026-10-17); 0x3101/02/04/07 stayed 0.
- ~~Channel 1's level key~~ (channel, input type), see 0x3401 (`captures/inputs.decoded.txt`).
- The app shows no percentages either; approximate 50% gave 16 and 100% gave 32, so percent = raw / 32.
- Slot 0. ~~Whether 0x3445 edits are saved into the tone~~: not until SET 0x3446 = 03 04 NN ff ff 00 (app capture 4).
- ~~0x3446 op 08 (discard edits?)~~ Discard, heard from the Mac (`captures/preset-edit-listen.*`).
- ~~Whether SET works from the Mac without the app's connect sequence~~ **It does** (2026-10-16 20:39, `captures/tuner-test-1.log`): no datetime/handshake needed, no ACKs needed.

## Logs
- `captures/app-capture-6-save.pklg` (+ `.decoded.txt`, `.markers.log`): JBL app on channel 1: Feathered Blues with delay time at max saved as test1 (0x35, Pop), test1 with reverb off saved as test2 (0x36), test2 renamed test3, test3 and test1 deleted, Feathered Blues edited and discarded, then reset to factory (19:18–19:22, 2026-10-18). Script: `capture-preset-edit.sh save`
- `captures/app-capture-6-gate.pklg`, `-comp.pklg`, `-reverb.pklg` (+ `.decoded.txt`, `.markers.log`): JBL app on Feathered Blues, channel 1: each pedal off and on, knobs swept, the gate's other model (19:05–19:15, 2026-10-18). Script: `capture-preset-edit.sh gate|comp|reverb`
- `captures/app-capture-6-dist.pklg` (+ `.decoded.txt`, `.markers.log`): JBL app on Feathered Blues, channel 1: each distortion model's knobs swept, discard, then Tremolo's Shape stepped 0 → 4 (18:54–19:02, 2026-10-18). Script: `capture-preset-edit.sh dist`
- `captures/app-capture-6-fx.pklg` (+ `.decoded.txt`): JBL app on Feathered Blues, channel 1: every FX model's knobs swept min → max (18:45–18:51, 2026-10-18), no spoken prompts
- `captures/app-capture-6-cab.pklg` (+ `.decoded.txt`, `.markers.log`): JBL app on Feathered Blues, channel 1: every cabinet in the list in order, then discard (18:37–18:40, 2026-10-18). Script: `capture-preset-edit.sh cab`
- `captures/app-capture-6-amp.pklg` (+ `.decoded.txt`, `.markers.log`): JBL app on Feathered Blues, channel 1: Yellow Tweed's five knobs swept, then every amp in the list in order, then discard (18:23–18:31, 2026-10-18). Script: `capture-preset-edit.sh amp`
- `captures/app-capture-6-delay.pklg` (+ `.decoded.txt`, `.markers.log`): JBL app on Feathered Blues, channel 1: each delay model's knobs swept min → max → middle, tap tempo, then discard (18:04–18:15, 2026-10-18). Script: `capture-preset-edit.sh delay`
- `captures/preset-edit-listen.listen.log` (+ `.timeline.log`, `.markers.log`, `.decoded.txt`): guitar in channel 1 on Feathered Blues; the Mac sends op 04 params: delay mix 50 + time 800, time 100 + feedback 60, discard, amp param 0 at 100 then 0, discard (18:19–18:20, 2026-10-18). **All heard.** Script: `capture-preset-edit.sh listen` with CH=1 ORIG=0d. An earlier run (18:00) sent the same edits as op 01 blocks and none was heard
- `captures/probe-param-edit-0.log`, `captures/probe-param-edit-1.log`: current tones (channel 1 on Feathered Blues 0x0d, channel 3 on 0x0f), Feathered Blues' blocks, then from the Mac its delay time 250 → 800 ms with 0x3445 op 01, 0x3444 re-read (still 250), op 08 discard, re-read (17:56–17:58, 2026-10-18). No guitar was playing
- `captures/tuner.listen.log` (+ `.timeline.log`, `.markers.log`, `.decoded.txt`): tuner kept on from the Mac while one guitar plays low E in channel 3, then A in channel 1, with the speaker's channel selection switched at each step (17:34–17:37, 2026-10-18). Script: `capture-tuner.sh`
- `captures/ch1-guitar.listen.log` (+ `.timeline.log`, `.markers.log`, `.decoded.txt`): the Mac switches channel 1's tone 0x1b → 01 → 0x1b, turns its delay on and off, runs the tuner, polling 0x3441 = 01/03 every 3 s (17:10–17:12, 2026-10-18). Tone and delay changes were heard; no guitar was plugged in, so the tuner saw nothing. Script: `capture-ch1-guitar.sh`
- `captures/probe-ch1-tone.log`: SET 0x3441 = 01/03, tone details of 0x1b ("Bypassed") and SET 0x3402 = 01 (17:10, 2026-10-18)
- `captures/ch2-controls.listen.log` (+ `.timeline.log`, `.markers.log`, `.decoded.txt`): channel 2 with a mic (Delay, Reverb up and down, Bass up), then line in (Bass, Mid, Treble up and down), then the mic back in (16:56–17:01, 2026-10-18). Script: `capture-ch2-controls.sh`
- `captures/probe-mic-block.log`: GET 0x0c00–0x0c17 from the Mac (17:01, 2026-10-18)
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
