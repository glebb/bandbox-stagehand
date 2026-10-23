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

print(failures == 0 ? "PASS" : "FAIL: \(failures)")
exit(failures == 0 ? 0 : 1)
