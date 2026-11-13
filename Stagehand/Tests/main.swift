// Tests for the parts that need no speaker: SysEx reassembly, reading the Rocksmith companion's
// song tones (ScratchTones.swift), planning a scratch tone's writes, and banks. Run: ./test.sh
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String, file: String = #file, line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

/// SysEx as the companion sends it (rs-mac-companion app/Sources/MIDIOut.swift): UMP SysEx7,
/// 6 bytes a message, complete / start / continue / end.
func umpSysEx(_ data: [UInt8]) -> [UInt32] {
    let chunks = stride(from: 0, to: max(data.count, 1), by: 6).map { Array(data[$0 ..< min($0 + 6, data.count)]) }
    return chunks.enumerated().flatMap { i, chunk -> [UInt32] in
        let status: UInt32 = chunks.count == 1 ? 0 : i == 0 ? 1 : i == chunks.count - 1 ? 3 : 2
        let b = (chunk + [0, 0, 0, 0, 0, 0]).map(UInt32.init)
        return [0x3000_0000 | status << 20 | UInt32(chunk.count) << 16 | b[0] << 8 | b[1],
                b[2] << 24 | b[3] << 16 | b[4] << 8 | b[5]]
    }
}

func message(_ json: String) -> [UInt8] { [SongTonesRequest.manufacturer] + Array(json.utf8) }

let song = #"{"artist":"Skid Row","kind":"song-tones","bank":"Classic rock","banks":["Soft"," Classic rock","Metal","",3],"song":"18 And Life","tones":["#
    + #"{"base":"Clean","key":"skid18an_clean","program":8,"set":{"Delay":{"on":false},"FX":{"Mix":35,"model":"Chorus","on":true},"Reverb":{"Mix":25,"on":true}}},"#
    + #"{"base":"Heavy","key":"skid18an_dist","program":9,"set":{"Delay":{"Fdbk":30,"Mix":80,"Time":5000,"model":"Analog Echo","on":true},"FX":{"on":false}}},"#
    + #"{"base":"Lead","key":"skid18an_solo","program":10,"set":{"Amp":{"Drive":100},"Delay":{"model":"Space Echo","on":true},"FX":{"Bogus":3,"on":true}}}"#
    + #"],"v":1}"#

// SysEx reassembly: split across feeds, with a Program Change in between.
do {
    var a = SysExAssembler()
    let words = umpSysEx(message(song))
    let pc: UInt32 = 0x20C0_0800
    let first = a.feed(Array(words[..<10]) + [pc])
    let rest = a.feed(words[10...])
    check(first.isEmpty, "no message before the end")
    check(rest == [message(song)], "the message comes back whole")
    check(MIDIMessage.parse([pc] + words).map(\.number) == [8], "the parser still sees the Program Change only")
    check(a.feed(umpSysEx([0x7D, 1, 2])) == [[0x7D, 1, 2]], "a short message in one packet")
    check(a.feed(Array(umpSysEx(message(song)).dropFirst(2))).isEmpty, "a message without its start is dropped")
}

// Reading the request.
let request = SongTonesRequest.parse(message(song))
check(request != nil, "the song tones parse")
if let r = request {
    check(r.song == "18 And Life" && r.bank == "Classic rock" && r.tones.count == 3, "header and three tones")
    check(r.banks == ["Soft", "Classic rock", "Metal"], "the bank names")
    check(r.tones.map(\.slot) == [0, 2, 3], "templates Clean, Heavy, Lead")
    check(r.tones[0].changes[.fx] == .init(on: true, model: 0x0B, knobs: ["Mix": 35]), "FX Chorus at Mix 35")
    check(r.tones[0].changes[.delay] == .init(on: false), "delay off")
    check(r.tones[2].changes[.amp] == nil, "the amp can't be changed")
    check(r.tones[2].changes[.delay] == nil, "an unknown model leaves the delay alone")
    check(r.warnings.contains { $0.contains("Amp can't be changed") }, "warned about the amp")
    check(r.warnings.contains { $0.contains("Space Echo") }, "warned about the unknown model")
    print("summary: \(r.summary)")
}
check(SongTonesRequest.parse([0x7E] + Array(song.utf8)) == nil, "another manufacturer is ignored")
check(SongTonesRequest.parse(message(#"{"v":1,"kind":"other","tones":[]}"#)) == nil, "another kind is ignored")
check(SongTonesRequest.parse(message("not json")) == nil, "text that isn't JSON is ignored")
let six = (0 ..< 6).map { #"{"base":"Clean","key":"t\#($0)","program":\#(8 + $0),"set":{}}"# }.joined(separator: ",")
check(SongTonesRequest.parse(message(#"{"v":1,"kind":"song-tones","tones":[\#(six)]}"#))?.tones.count == 5, "at most five tones")

// Version 2: Rocksmith's effects, mapped to the BandBox here.
let song2 = #"{"v":2,"kind":"song-tones","song":"18 And Life","artist":"Skid Row","tempo":120,"style":"Classic rock","styles":["Soft","Classic rock","Metal"],"tones":["#
    + #"{"program":8,"key":"c","category":"Clean","effects":{"modulation":{"kind":"chorus","mix":60},"reverb":{"mix":20}}},"#
    + #"{"program":9,"key":"d","category":"Heavy","effects":{"delay":{"kind":"tape","mix":30,"feedback":120}}},"#
    + #"{"program":10,"key":"l","category":"Lead","effects":{"modulation":{"kind":"phaser","mix":50},"delay":{"kind":"analog","time_ms":1500}}}]}"#
if let r = SongTonesRequest.parse(message(song2)) {
    check(r.bank == "Classic rock" && r.banks == ["Soft", "Classic rock", "Metal"], "v2: the style names the bank")
    let spaced = SongTonesRequest.parse(message(song2.replacingOccurrences(of: #""style":"Classic rock""#, with: #""style":" Classic rock ""#)))
    check(spaced?.bank == "Classic rock", "v2: spaces around the style are dropped")
    let long = String(repeating: "x", count: 40)
    let longStyle = SongTonesRequest.parse(message(song2.replacingOccurrences(of: #""Classic rock""#, with: "\"\(long)\"")))
    check(longStyle?.bank == String(long.prefix(SongTonesRequest.maxBankName)) && longStyle?.banks[1] == longStyle?.bank,
          "v2: a long style is cut, the same in style and styles")
    check(r.tones.map(\.slot) == [0, 2, 3], "v2: templates by category")
    check(r.tones[0].changes[.fx] == .init(on: true, model: 0x0B, knobs: ["Mix": 35]), "v2: chorus, mix kept at 35")
    check(r.tones[0].changes[.delay] == .init(on: false), "v2: no delay turns it off")
    check(r.tones[0].changes[.reverb] == .init(on: true, knobs: ["Mix": 20]), "v2: reverb mix 20")
    let tape = r.tones[1].changes[.delay]
    check(tape?.model.flatMap { EffectSlot.delay.model($0)?.name } == "Echopress 900", "v2: tape delay is Echopress 900")
    check(tape?.knobs == ["Time": 500, "Mix": 30, "Fdbk": 100], "v2: time from the tempo, feedback at most 100")
    check(r.tones[1].changes[.reverb] == nil, "v2: no reverb leaves the template's")
    check(r.tones[2].changes[.fx]?.model.flatMap { EffectSlot.fx.model($0)?.name } == "Green Phaser"
          && r.tones[2].changes[.fx]?.knobs == [:], "v2: phaser, without a mix")
    check(r.tones[2].changes[.delay]?.knobs["Time"] == 1000, "v2: time at most 1000 ms")
    check(r.warnings.isEmpty, "v2: no warnings (\(r.warnings))")
    check(r.tones.map(\.program) == [8, 9, 10], "v2: the message's programs")
} else {
    check(false, "v2 parses")
}

// Programs: as the message names them, 8 + index when it doesn't, kept to 0-127.
let programs = #"{"v":2,"kind":"song-tones","tones":[{"program":20,"category":"Clean"},{"category":"Lead"},{"program":200,"category":"Heavy"}]}"#
check(SongTonesRequest.parse(message(programs))?.tones.map(\.program) == [20, 9, 127], "programs 20, 8 + 1, at most 127")

// Scratch tone names: "Song n", and "RS n" from before.
check(ScratchFiller.isScratchName("Song 1") && ScratchFiller.isScratchName("RS 5"), "scratch names, new and old")
check(!ScratchFiller.isScratchName("Song 6") && !ScratchFiller.isScratchName("My Song 1"), "other names aren't")

// Match amps: the game's amp names a family; anything else leaves the template's.
func amp(_ name: String?) -> UInt16? { name.flatMap { n in EffectSlot.amp.models.first { $0.name == n }?.id } }
func cab(_ name: String) -> UInt16? { EffectSlot.cab.models.first { $0.name == name }?.id }
check(GearMatch.Family(gear: "Amp_MarshallJCM800") == .british && GearMatch.Family(gear: "Amp_HG500") == .british, "Marshalls, the HG500 too")
check(GearMatch.Family(gear: "Amp_CA100") == .highGain && GearMatch.Family(gear: "Amp_CA85") == .boogie
      && GearMatch.Family(gear: "Amp_TW22") == .american, "high gain, American")
check(GearMatch.Family(gear: "Amp_EN30") == .chime && GearMatch.Family(gear: "Amp_CS90") == .jazz, "chime, jazz")
check(GearMatch.Family(gear: "Bass_Amp_HT300B") == nil && GearMatch.Family(gear: "DI_Amp_TubePre") == nil
      && GearMatch.Family(gear: "Amp_Unknown") == nil, "a bass, a DI and an unknown amp have none")
check(GearMatch.Family.allCases.allSatisfy { $0.amps.allSatisfy { BandBoxCalibration.amps[$0] != nil && GearMatch.ampDefaults[$0] != nil } },
      "every stand-in amp was measured")
check(GearMatch.cab(gear: "Cab_Marshall1960a_57_Cone") == cab("UK 1960 4x12") && GearMatch.cab(gear: "Cab_CA412C_Ribbon_Edge") == cab("Mebo 4x12")
      && GearMatch.cab(gear: "Cab_EN212C_57_Cone") == cab("Voks 2x12") && GearMatch.cab(gear: "Cab_Marshall1936_57_Cone") == cab("UK 2550 2x12"), "cabs")
check(GearMatch.cab(gear: "Cab_PA600C_57_Cone") == nil && GearMatch.cab(gear: "Bass_Cab_AT810BC_57_Cone") == nil, "a PA and a bass cab keep the template's")
check(BandBoxMapping.canSwitchAmp(from: 0x0306) && !BandBoxMapping.canSwitchAmp(from: 0x0806), "guitar amps only")

// The tables, read: an amp follows a quiet input and stops following a loud one; more Drive, more saturated.
check(abs(GearMatch.value([(0, 0), (10, 20)], at: 5) - 10) < 1e-9 && abs(GearMatch.value([(0, 0), (10, 20)], at: 15) - 30) < 1e-9, "lines, and on past the ends")
check(abs(GearMatch.inverse([(20, -15.6), (50, 0), (100, 12.1)], of: 0) - 50) < 1e-9, "the inverse")
check(GearMatch.saturation(0x0006, drive: 30, input: 0)! < 0.15, "American Clean is clean")
check(GearMatch.saturation(0x0706, drive: 100, input: 8)! > 0.9, "US Metal at full is saturated")
check(GearMatch.saturation(0x0306, drive: 80, input: 8)! > GearMatch.saturation(0x0306, drive: 20, input: 8)!, "more Drive, more saturated")
check(GearMatch.saturation(0x0806, drive: 50, input: 0) == nil, "the bass amp wasn't measured")
check(GearMatch.target(drive: 0.9) > GearMatch.target(drive: 0.5) && GearMatch.target(drive: 0.5) > GearMatch.target(drive: 0.1), "the drive asks for more")

let withAmp = #"""
    {"v":2,"kind":"song-tones","style":"Metal","main_amp":"Amp_CA100","tones":[
     {"key":"a","category":"Heavy","drive":0.9,"amp":{"gear":"Amp_CA100","gain":80,"mid":30},"effects":{}},
     {"key":"b","category":"Clean","drive":0.1,"effects":{},
      "rig":{"Amp":{"gear":"Amp_TW22","knobs":{"Gain":20,"Bass":40,"Mid":50,"Treble":60,"":3,"Bright":true}},
             "Cabinet":{"gear":"Cab_TW112C_57_Cone","knobs":{}},"PrePedal1":{"gear":"Pedal_GermaniumDrive","knobs":{"Gain":40,"Tone":70}}}},
     {"key":"c","category":"Lead","amp":{"gear":"Amp_CA100","gain":80},"effects":{},
      "set":{"amp":{"model":"US Metal","Drive":60,"Volume":45},"Cab":{"model":"Mebo 4x12"},"Gate":{"on":true},"Wah":{"on":true},"Delay":{"on":false}}}]}
    """#
let amps = SongTonesRequest.parse(message(withAmp))
check(amps?.tones[0].rig == ["Amp": .init(gear: "Amp_CA100", knobs: ["Gain": 80, "Mid": 30])] && amps?.tones[0].drive == 0.9, "a rig from the message's amp")
check(amps?.tones[1].rig["Amp"] == .init(gear: "Amp_TW22", knobs: ["Gain": 20, "Bass": 40, "Mid": 50, "Treble": 60, "": 3])
      && amps?.tones[1].rig["PrePedal1"]?.knobs == ["Gain": 40, "Tone": 70] && amps?.tones[1].rig.count == 3, "the whole rig, knobs that are numbers")
check(amps?.summary.contains("amp Amp_CA100") == true, "the summary names the amp")
check(amps?.tones[2].changes[.amp] == .init(on: nil, model: amp("US Metal"), knobs: ["Drive": 60, "Volume": 45])
      && amps?.tones[2].changes[.cab]?.model == cab("Mebo 4x12") && amps?.tones[2].changes[.gate] == .init(on: true)
      && amps?.tones[2].changes[.delay] == .init(on: false) && amps?.tones[2].named == [.amp, .cab, .gate, .delay],
      "version 2 sets any pedal by name")
check(amps?.warnings == ["c: no pedal Wah"], "and warns about one that isn't: \(amps?.warnings ?? [])")
check(SongTonesRequest.parse(message(#"{"v":1,"kind":"song-tones","tones":[{"base":"Heavy","drive":0.9,"amp":{"gear":"Amp_CA100"}}]}"#))?
    .tones[0].rig.isEmpty == true, "version 1 has no rig")


// Planning. A template like Brit Crunch: every slot, FX Green Phaser on, delay Pure Echo off.
func block(_ slot: EffectSlot, _ model: UInt16, on: Bool, _ params: [(UInt8, Float)]) -> EffectBlock {
    EffectBlock(slot: slot.rawValue, model: model, bypassed: !on, params: params.map { EffectParam(id: $0.0, value: $0.1) })
}
let template = ToneDetails(id: 0x0F, name: "Brit Crunch", blocks: [
    block(.gate, 0x00, on: true, [(0, 30)]),
    block(.compressor, 0x01, on: false, [(0, 50), (1, 4), (2, 20), (4, 50)]),
    block(.distortion, 0x04, on: true, [(0, 40), (1, 50), (2, 60)]),
    block(.amp, 0x0306, on: true, [(0, 55), (1, 50), (2, 60), (3, 55), (4, 70)]),
    block(.cab, 0x0608, on: true, []),
    block(.fx, 0x0F, on: true, [(0, 30), (1, 50), (2, 20)]),
    block(.delay, 0x14, on: false, [(0, 20), (1, 450), (2, 30)]),
    block(.reverb, 0x1B, on: true, [(0, 10), (2, 40), (4, 20)]),
])
if let r = request {
    var warnings: [String] = []
    let clean = ScratchPlan.target(template: template, tone: r.tones[0], warnings: &warnings)
    let fx = clean.first { $0.slot == EffectSlot.fx.rawValue }!
    check(fx.model == 0x0B && !fx.bypassed && fx.params == [4: 35], "FX becomes Chorus, Mix 35, the rest its defaults")
    check(clean.first { $0.slot == EffectSlot.reverb.rawValue }!.params[4] == 25, "reverb Mix 25")
    check(clean.first { $0.slot == EffectSlot.amp.rawValue } == KnownBlock(template.block(.amp)!), "the amp is the template's")
    check(clean.first { $0.slot == EffectSlot.delay.rawValue }!.bypassed, "delay stays off")

    let heavy = ScratchPlan.target(template: template, tone: r.tones[1], warnings: &warnings)
    let delay = heavy.first { $0.slot == EffectSlot.delay.rawValue }!
    check(delay.model == 0x15 && delay.params == [0: 80, 1: 1000, 2: 30] && !delay.bypassed, "Analog Echo, Time kept to 1000 ms")
    check(heavy.first { $0.slot == EffectSlot.fx.rawValue }!.bypassed, "FX off")

    _ = ScratchPlan.target(template: template, tone: r.tones[2], warnings: &warnings)
    check(warnings.contains { $0.contains("no knob Bogus") }, "warned about an unknown knob")

    // From nothing known: every slot gets its model, knobs and on/off.
    let all = ScratchPlan.edits(from: nil, to: clean)
    check(all.filter { if case .model = $0 { true } else { false } }.count == 8, "eight model writes when nothing is known")
    let filled = ScratchPlan.applying(all, to: nil)
    check(filled == clean.sorted { $0.slot < $1.slot }, "the writes give the target")
    check(ScratchPlan.edits(from: filled, to: clean).isEmpty, "nothing to write the second time")

    // The next song's tone on the same template: only what differs.
    let next = ScratchPlan.edits(from: filled, to: heavy)
    check(next == [
        .model(slot: 5, model: 0x0F), .param(slot: 5, model: 0x0F, param: 0, value: 30),
        .param(slot: 5, model: 0x0F, param: 1, value: 50), .param(slot: 5, model: 0x0F, param: 2, value: 20),
        .bypass(slot: 5, model: 0x0F, bypassed: true, params: [EffectParam(id: 0, value: 30), EffectParam(id: 1, value: 50), EffectParam(id: 2, value: 20)]),
        .model(slot: 6, model: 0x15), .param(slot: 6, model: 0x15, param: 0, value: 80),
        .param(slot: 6, model: 0x15, param: 1, value: 1000), .param(slot: 6, model: 0x15, param: 2, value: 30),
        .bypass(slot: 6, model: 0x15, bypassed: false, params: [EffectParam(id: 0, value: 80), EffectParam(id: 1, value: 1000), EffectParam(id: 2, value: 30)]),
        .param(slot: 7, model: 0x1B, param: 4, value: 20),
    ], "only FX, Delay and Reverb change: \(next)")
    check(ScratchPlan.edits(from: ScratchPlan.applying(next, to: filled), to: heavy).isEmpty, "and then nothing")
}

// The bytes, as BandBoxClient and protocol-notes.md have them.
// Match amps in the plan: off changes nothing; on, the rig's amp, drive, cab and pedal, at the template's level.
if let a = amps {
    var warnings: [String] = [], notes: [String] = []
    func tables(_ blocks: [KnownBlock]) -> Double? {
        func b(_ slot: EffectSlot) -> KnownBlock? { blocks.first { $0.slot == slot.rawValue } }
        return GearMatch.level(amp: b(.amp)!, cab: b(.cab), input: GearMatch.input(compressor: b(.compressor), distortion: b(.distortion)))
    }
    let was = template.blocks.map(KnownBlock.init)
    let off = ScratchPlan.target(template: template, tone: a.tones[0], warnings: &warnings)
    check(off.first { $0.slot == 3 }?.model == 0x0306, "Match amps off: the template's amp")
    let heavy = ScratchPlan.target(template: template, tone: a.tones[0], matchAmp: true, warnings: &warnings, notes: &notes)
    let heavyAmp = heavy.first { $0.slot == 3 }!
    check(heavyAmp.model == amp("US Metal") && !heavyAmp.bypassed, "a heavy Rectifier: US Metal, on")
    check(GearMatch.saturation(heavyAmp.model, drive: Double(heavyAmp.params[0]!), input: GearMatch.input(compressor: nil, distortion: nil))! > 0.8,
          "driven hard")
    check(heavyAmp.params[2] == 30 && heavyAmp.params[1] == 67, "the game's Mid, the model's own Bass")
    check(heavy.first { $0.slot == 2 }!.bypassed, "no pedal in the rig: the template's Precision Drive goes off")
    check(heavy.first { $0.slot == 4 } == was.first { $0.slot == 4 }, "no cab in the rig: the template's")
    check(abs(tables(heavy)! - tables(was)!) < 0.6, "as loud as the template: \(tables(heavy)!) and \(tables(was)!)")
    check(notes.count == 1 && notes[0].contains("Amp_CA100") && notes[0].contains("Precision Drive off"), "what was picked: \(notes)")

    let clean = ScratchPlan.target(template: template, tone: a.tones[1], matchAmp: true, warnings: &warnings, notes: &notes)
    let cleanAmp = clean.first { $0.slot == 3 }!
    check(cleanAmp.model == amp("American Clean") && cleanAmp.params[1] == 40 && cleanAmp.params[2] == 50 && cleanAmp.params[3] == 60,
          "a clean Tweed: American Clean with the game's tone knobs")
    check(clean.first { $0.slot == 4 }?.model == cab("TR65 2x12") && clean.first { $0.slot == 4 }?.bypassed == false, "the rig's cab, still on")
    let pedal = clean.first { $0.slot == 2 }!
    check(pedal.model == 0x04 && !pedal.bypassed && pedal.params == [0: 22, 1: 70, 2: 100], "the rig's drive pedal, by its gain and tone")
    check(abs(tables(clean)! - tables(was)!) < 0.6 || cleanAmp.params[4] == 100, "as loud as the template, or the Volume at its end")
    let edits = ScratchPlan.edits(from: was, to: clean)
    check(edits.contains(.model(slot: 4, model: cab("TR65 2x12")!)) && !edits.contains { if case .bypass(slot: 4, _, _, _) = $0 { true } else { false } },
          "a cab is one write, op 03")
    check(ScratchPlan.applying(edits, to: was).first { $0.slot == 3 } == cleanAmp, "the writes give the amp with all five knobs")

    // What a message sets by name comes last.
    let named = ScratchPlan.target(template: template, tone: a.tones[2], matchAmp: true, warnings: &warnings, notes: &notes)
    check(named.first { $0.slot == 3 }?.model == amp("US Metal") && named.first { $0.slot == 3 }?.params[0] == 60
          && named.first { $0.slot == 3 }?.params[4] == 45 && named.first { $0.slot == 3 }?.bypassed == false, "the named amp and its knobs")
    check(named.first { $0.slot == 4 }?.model == cab("Mebo 4x12") && named.first { $0.slot == 0 }?.bypassed == false, "the named cab, the gate on")
    check(notes.count == 2, "no drive in the message: no match for that tone")

    // What stays as it is.
    func rigged(_ gear: String, drive: Double? = 0.9, pedal: String? = nil) -> SongTonesRequest.Tone {
        var rig = ["Amp": SongTonesRequest.RigItem(gear: gear, knobs: ["Gain": 70])]
        if let pedal { rig["PrePedal1"] = .init(gear: pedal) }
        return SongTonesRequest.Tone(key: "x", program: 8, slot: 0, changes: [:], drive: drive, rig: rig)
    }
    check(GearMatch.match(template: template, tone: rigged("Bass_Amp_HT300B")) == nil && GearMatch.match(template: template, tone: rigged("DI_Amp_TubePre")) == nil
          && GearMatch.match(template: template, tone: rigged("Amp_Unknown")) == nil, "a bass, a DI, an unknown amp")
    check(GearMatch.match(template: template, tone: rigged("Amp_CA100", drive: nil)) == nil, "no drive")
    check(GearMatch.match(template: template, tone: rigged("Amp_TW22", pedal: "Pedal_AcousticEmulator")) == nil, "an acoustic sound")
    let acoustic = ToneDetails(id: 2, name: "x", blocks: [block(.amp, 0x001D, on: true, [])])
    check(GearMatch.match(template: acoustic, tone: rigged("Amp_CA100")) == nil, "an acoustic template")
    let off2 = ToneDetails(id: 3, name: "x", blocks: [block(.amp, 0x0306, on: false, [])])
    check(GearMatch.match(template: off2, tone: rigged("Amp_CA100")) == nil, "an amp that's off stays off")
    // More drive never picks a less saturated setting, on any family.
    for gear in ["Amp_TW22", "Amp_CS90", "Amp_EN30", "Amp_MarshallJCM800", "Amp_CA100"] {
        let picked = stride(from: 0.0, through: 1.0, by: 0.1).map { d -> Double in
            let m = GearMatch.match(template: template, tone: rigged(gear, drive: d))!.blocks[3]!
            return GearMatch.saturation(m.model, drive: Double(m.params[0]!), input: BandBoxCalibration.guitar)!
        }
        check(zip(picked, picked.dropFirst()).allSatisfy { $0 <= $1 + 0.1 }, "\(gear): more drive, more saturated: \(picked.map { String(format: "%.2f", $0) })")
        print(gear, stride(from: 0.0, through: 1.0, by: 0.1).map { d -> String in
            let m = GearMatch.match(template: template, tone: rigged(gear, drive: d))!.blocks[3]!
            return "\(EffectSlot.amp.model(m.model)!.name.split(separator: " ").map { String($0.prefix(1)) }.joined())\(Int(m.params[0]!))/\(Int(m.params[4]!))"
        }.joined(separator: " "))
    }
    check(warnings.isEmpty, "no warnings: \(warnings)")
    notes.forEach { print("match:", $0) }
}

check(ScratchPlan.Edit.param(slot: 6, model: 0x14, param: 1, value: 800).value(channel: 3, tone: 0x40)
      == [3, 0x40, 4, 6, 0x14, 0, 0xFF, 1, 1] + BandBoxProtocol.f32(800), "op 04 bytes")
check(ScratchPlan.Edit.model(slot: 5, model: 0x0B).value(channel: 3, tone: 0x40) == [3, 0x40, 2, 5, 0x0B, 0, 0xFF, 0], "op 02 bytes")
check(ScratchPlan.Edit.model(slot: 3, model: 0x0706).value(channel: 1, tone: 0x40) == [1, 0x40, 3, 3, 0x06, 0x07, 0xFF, 0], "op 03 for an amp")
check(ScratchPlan.Edit.bypass(slot: 7, model: 0x1B, bypassed: true, params: [EffectParam(id: 4, value: 20)]).value(channel: 3, tone: 0x40)
      == [3, 0x40, 1, 7, 0x1B, 0, 1, 1, 4] + BandBoxProtocol.f32(20), "op 01 bytes")

// Banks (ToneAssignments): this test binary's own defaults, cleared before and after.
let domain = ProcessInfo.processInfo.processName
UserDefaults.standard.removePersistentDomain(forName: domain)
UserDefaults.standard.set([5, 6, 7, 8], forKey: "toneSlots")   // buttons saved before there were banks
do {
    let a = ToneAssignments()
    let clean = ToneSlot.all[0]
    check(a.banks.map(\.name) == ["Main"] && a.tone(clean, channel: 3) == 5, "the old buttons become the bank Main")
    a.addBank(named: "Metal")
    check(a.bankName == "Metal" && a.tone(clean, channel: 3) == 5, "a new bank starts as a copy and is current")
    a.assign(30, to: 0, channel: 3)
    check(a.tone(clean, channel: 3, bank: 0) == 5 && a.tone(clean, channel: 3, bank: 1) == 30, "assigning changes only the current bank")
    check(a.bank(named: " metal") == 1 && a.bank(named: "Soft") == nil, "banks are found by name, any case")
    a.renameBank(to: "Metal ")
    check(a.bank(named: "metal") == 1, "a bank saved with spaces around its name is still found")
    a.renameBank(to: "Metal")
    let again = ToneAssignments()
    check(again.bankName == "Metal" && again.tone(clean, channel: 3) == 30 && again.banks.count == 2, "banks are kept")
    a.addBank(named: "Soft", copying: 0)
    check(a.bankName == "Metal" && a.tone(clean, channel: 3, bank: 2) == 5, "a copy of Main, without switching to it")
    a.selectBank(2)
    a.deleteBank()
    a.selectBank(0)
    check(a.tone(clean, channel: 3) == 5, "back to Main")
    a.selectBank(1)
    a.deleteBank()
    check(a.banks.map(\.name) == ["Main"] && a.bankName == "Main" && a.tone(clean, channel: 3) == 5, "deleting goes back to the one before")
    a.deleteBank()
    check(a.banks.count == 1, "the last bank stays")
}
UserDefaults.standard.removePersistentDomain(forName: domain)

// Broken settings: a bank with a short channel 3 and no channel 1, a binding to a tone slot past the fourth.
do {
    let broken = Bank(name: "Odd", tones: [3: [9, 9]], names: [3: ["x"], 1: ["a", "b", "c", "d"]])
    UserDefaults.standard.set(try? JSONEncoder().encode([broken]), forKey: "banks")
    let a = ToneAssignments()
    let lead = ToneSlot.all[3]
    check(a.tone(lead, channel: 3) == lead.defaultTone && a.tone(lead, channel: 1) == lead.defaultTone,
          "a short or missing channel gets the slots' own tones")
    check(a.name(lead, channel: 1) == "d" && a.name(lead, channel: 3) == lead.name, "names that fit are kept")
    a.assign(40, to: 3, channel: 1)
    check(a.tone(lead, channel: 1) == 40, "a channel that was missing can be assigned")
    let bindings = [MIDIBinding(trigger: MIDITrigger(kind: .program, number: 0), action: .tone(slot: 7, .primary)),
                    MIDIBinding(trigger: MIDITrigger(kind: .program, number: 1), action: .tone(slot: 1, .primary))]
    UserDefaults.standard.set(try? JSONEncoder().encode(bindings), forKey: "midiBindings")
    check(MIDIInput.savedBindings() == [bindings[1]], "a binding to a slot that doesn't exist is dropped")
}
UserDefaults.standard.removePersistentDomain(forName: domain)

// The DI's writes and reads, as the JBL app's Output page makes them (app-teardown.md).
do {
    check([UInt8](BandBoxProtocol.set(Property.outputLocation, [OutputLocation.computer.rawValue]))
          == [0x00, 0xDD, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x80, 0x31, 0x01, 0x00, 0x02], "output to the computer: SET 0x3180 = 02")
    check([UInt8](BandBoxProtocol.set(Property.directMonitor, [0]))
          == [0x00, 0xDD, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x87, 0x31, 0x01, 0x00, 0x00], "direct monitor off: SET 0x3187 = 00")
    check(USBStatus(0x87).hasComputer && USBStatus(0x87).source == .computer, "plugged in, USB audio: a computer")
    check(USBStatus(0x83).plugged && !USBStatus(0x83).hasComputer && USBStatus(0x83).source == .usbDrive, "a USB drive isn't a computer")
    check(!USBStatus(0x07).plugged && !USBStatus(0x07).hasComputer, "nothing plugged in")
    check(USBStatus(0xFF).source == nil, "an unknown source")
    let reply = BandBoxProtocol.records([0x00, 0x00, 0x87, 0x31, 0x01, 0x00, 0x01, 0x05, 0x38, 0x03, 0x00, 0x01, 0x0D, 0x0E])
    check(reply.records.map(\.id) == [Property.directMonitor, Property.capabilities], "a GET reply with direct monitor and capabilities")
    check(Set(reply.records[1].value).contains(Capability.outputToComputer.rawValue), "output to the computer in the capability list")
}

// The chromatic tuner (0x3107 / 0x3108, from the JBL app's V5ChromaticTuningResult and ChromaticTuningView).
do {
    check([UInt8](BandBoxProtocol.set(Property.tunerChromatic, [1]))
          == [0x00, 0xDD, 0x02, 0x00, 0x01, 0x00, 0x05, 0x00, 0x07, 0x31, 0x01, 0x00, 0x01], "chromatic on: SET 0x3107 = 01")
    func sample(_ note: Int8, _ cents: Int8, heard: Float, signal: UInt8 = 1) -> [UInt8] {
        [UInt8(bitPattern: note)] + BandBoxProtocol.f32(82.41) + [UInt8(bitPattern: cents)] + BandBoxProtocol.f32(heard) + [signal]
    }
    let lowD = BandBoxProtocol.chromaticReading(sample(-31, -7, heard: 73.1))
    check(lowD?.noteName == "D" && lowD?.octave == 2 && lowD?.cents == -7 && lowD?.hasSignal == true, "D2, 7 cents flat (drop D)")
    check(abs((lowD?.frequency ?? 0) - 73.1) < 0.01, "the frequency heard")
    let a4 = BandBoxProtocol.chromaticReading(sample(0, 12, heard: 443))
    check(a4?.noteName == "A" && a4?.octave == 4 && a4?.cents == 12, "A4, 12 cents sharp")
    let cSharp = BandBoxProtocol.chromaticReading(sample(-20, 0, heard: 138.6))
    check(cSharp?.noteName == "C♯" && cSharp?.octave == 3, "C♯3")
    let bassE = BandBoxProtocol.chromaticReading(sample(-41, 0, heard: 41.2))
    check(bassE?.noteName == "E" && bassE?.octave == 1, "E1, below the app's C2–B4")
    check(BandBoxProtocol.chromaticReading(sample(0, 0, heard: 0, signal: 0))?.hasSignal == false, "no signal")
    check(BandBoxProtocol.chromaticReading(Array(sample(0, 0, heard: 440).prefix(10))) == nil, "a short sample is dropped")
}

print(failures == 0 ? "PASS" : "FAIL: \(failures)")
exit(failures == 0 ? 0 : 1)
