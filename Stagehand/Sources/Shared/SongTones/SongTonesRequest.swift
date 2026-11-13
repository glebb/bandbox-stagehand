import Foundation

// Song tones: a message any app can send Stagehand over MIDI to have it make a tone for each of a
// song's tones and play them by Program Change (the RS Companion sends one as a Rocksmith song
// loads). One SysEx: manufacturer 0x7D (non-commercial), then JSON. Version 2 describes the tones
// in plain terms and leaves the BandBox to Stagehand:
//
//   {"v": 2, "kind": "song-tones", "song": "18 And Life", "artist": "Skid Row", "tempo": 92.4,
//    "style": "Classic rock", "styles": ["Soft", "Classic rock", "Metal"],
//    "tones": [{"program": 8, "key": "skid18an_clean", "category": "Clean",
//               "effects": {"modulation": {"kind": "chorus", "mix": 60}, "reverb": {"mix": 25}}},
//              {"program": 9, "key": "skid18an_dist", "category": "Heavy",
//               "effects": {"delay": {"kind": "analog", "time_ms": 400, "mix": 30, "feedback": 20}}}]}
//
// "category": Clean, Crunch, Heavy or Lead, the tone slot it starts from (its template).
// "effects": delay (kind tape, analog, modulated or digital; time_ms, mix 0-100, feedback),
// modulation (kind chorus, flanger, phaser, tremolo or vibe; mix) and reverb (mix). Left out:
// the tone has none (a delay or modulation is switched off; the template's reverb stays).
// "program": the Program Change that plays it (0-127; 8 + its index if left out).
// "style": the bank the templates come from (the current bank if there's none by that name);
// "styles": every style the app may send, made as copies of Main if missing. "key" names the
// tone on screen; "song", "artist" and "tempo" (for a delay without a time) are optional.
// "drive" (how distorted the tone should sound, 0-1) and "rig" (every gear item of the tone by its
// slot: {"Amp": {"gear": "Amp_CA100", "knobs": {"Gain": 80, "Bass": 50}}, "Cabinet": {"gear":
// "Cab_CA412C_57_Cone"}, "PrePedal1": {"gear": "Pedal_GermaniumDrive", "knobs": {"Gain": 45}}}) are
// optional too, and only used with Match amps on ("amp": {"gear": ...} does for a rig with only an
// amp). Fields that aren't listed here are ignored.
//
// Each tone becomes a scratch tone: its template with only the FX, Delay and Reverb pedals
// changed, so it keeps the template's level. BandBoxMapping below picks the pedals. With Match
// amps on, a tone with a guitar amp also gets the amp, drive, tone knobs, cabinet and drive pedal
// nearest its rig, at the template's level (GearMatch.swift).
//
// A tone can also name the BandBox's own pedals, for an app that knows them: "set": {"Amp":
// {"model": "US Metal", "Drive": 60, "Volume": 45}, "Cab": {"model": "Mebo 4x12"}, "Delay": {"on":
// true, "model": "Analog Echo", "Time": 400, "Mix": 30}}, any of Gate, Comp, Dist, Amp, Cab, FX,
// Delay and Reverb, with the models and knobs as the JBL app names them. It is applied last, over
// everything else, and whoever sets Gate, Comp, Dist, Amp or Cab also sets the tone's level.
// Version 1 has only that: "bank", "banks", and per tone "base" (the category) and "set", where
// only FX, Delay and Reverb can be set.

/// A song tones message, checked against the pedals and models Stagehand knows.
struct SongTonesRequest: Equatable {
    static let manufacturer: UInt8 = 0x7D
    static let firstProgram = 8
    static let maxTones = 5           // scratch tones (a Rocksmith arrangement has up to five tones)
    /// The tone slots by the names a message uses for them, in ToneSlot order.
    static let slots = ["Clean", "Crunch", "Heavy", "Lead"]
    /// The only pedals a version 1 message may change: the others set the tone's level.
    static let pedals: [String: EffectSlot] = ["FX": .fx, "Delay": .delay, "Reverb": .reverb]
    /// Every pedal by its name, for a version 2 tone's "set".
    static let allPedals = Dictionary(uniqueKeysWithValues: EffectSlot.allCases.map { ($0.name, $0) })

    /// One item of a tone's rig, as the song has it: the game's name for the gear, and its knobs.
    struct RigItem: Equatable {
        let gear: String
        var knobs: [String: Double] = [:]
    }

    struct Tone: Equatable {
        let key: String
        let program: Int                    // the Program Change that plays it
        let slot: Int                       // the template: index into ToneSlot.all
        let changes: [EffectSlot: Change]
        var named: Set<EffectSlot> = []     // the pedals the message set by name ("set"): they win over a match
        var drive: Double? = nil            // how distorted it should sound, 0-1
        var rig: [String: RigItem] = [:]    // its gear by slot ("Amp", "Cabinet", "PrePedal1" …), for Match amps
    }

    /// What a song does to one pedal: on or off (nil: as the template has it), perhaps another model, knobs by name.
    struct Change: Equatable {
        var on: Bool?
        var model: UInt16?                  // nil: the template's model
        var knobs: [String: Float] = [:]
    }

    let song: String
    let artist: String
    let bank: String
    /// Every bank a message may name; Stagehand makes the missing ones (ScratchFiller).
    let banks: [String]
    let tones: [Tone]
    /// What was refused or guessed, for the log.
    let warnings: [String]

    /// The request in a SysEx message's bytes (between F0 and F7), or nil when the message isn't
    /// one: another manufacturer, not JSON, another kind or version.
    static func parse(_ sysex: [UInt8]) -> SongTonesRequest? {
        guard sysex.first == manufacturer,
              let json = try? JSONSerialization.jsonObject(with: Data(sysex.dropFirst())) as? [String: Any],
              json["kind"] as? String == "song-tones", let version = json["v"] as? Int, version == 1 || version == 2,
              let list = json["tones"] as? [[String: Any]] else { return nil }
        let v2 = version == 2
        let tempo = (json["tempo"] as? NSNumber)?.doubleValue
        var warnings: [String] = []
        if list.count > maxTones { warnings.append("\(list.count) tones, only the first \(maxTones) are made") }
        let tones = list.prefix(maxTones).enumerated().map { i, t in
            let key = t["key"] as? String ?? "tone \(i + 1)"
            let program = (t["program"] as? Int).map { min(max($0, 0), 127) } ?? firstProgram + i
            let base = t[v2 ? "category" : "base"] as? String ?? ""
            let slot = slots.firstIndex { $0.caseInsensitiveCompare(base) == .orderedSame } ?? {
                warnings.append("\(key): no tone slot \"\(base)\", using \(slots[0])")
                return 0
            }()
            var changes: [EffectSlot: Change] = [:]
            let set = v2 ? BandBoxMapping.pedals(t["effects"] as? [String: Any] ?? [:], tempo: tempo)
                         : t["set"] as? [String: Any] ?? [:]
            for (name, value) in set {
                guard let slot = pedals[name] else {
                    warnings.append("\(key): \(name) can't be changed, only FX, Delay and Reverb")
                    continue
                }
                guard let fields = value as? [String: Any], let change = change(slot, fields, key, &warnings) else { continue }
                changes[slot] = change
            }
            guard v2 else { return Tone(key: key, program: program, slot: slot, changes: changes) }
            // The BandBox's own pedals, named by the sender: over what the effects gave, and (in the plan) over a match.
            var named: Set<EffectSlot> = []
            for (name, value) in t["set"] as? [String: Any] ?? [:] {
                guard let slot = allPedals.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value else {
                    warnings.append("\(key): no pedal \(name)")
                    continue
                }
                guard let fields = value as? [String: Any], let change = change(slot, fields, key, &warnings,
                                                                                on: fields["on"] as? Bool) else { continue }
                changes[slot] = change
                named.insert(slot)
            }
            return Tone(key: key, program: program, slot: slot, changes: changes, named: named,
                        drive: (t["drive"] as? NSNumber)?.doubleValue, rig: rig(t))
        }
        return SongTonesRequest(song: json["song"] as? String ?? "", artist: json["artist"] as? String ?? "",
                                bank: bankName(json[v2 ? "style" : "bank"] as? String ?? ""),
                                banks: names(json[v2 ? "styles" : "banks"]),
                                tones: tones, warnings: warnings)
    }

    /// Bank names: text, trimmed, not empty, at most 16.
    private static func names(_ value: Any?) -> [String] {
        let list = (value as? [Any] ?? []).compactMap { ($0 as? String).map(bankName) }
        return Array(list.filter { !$0.isEmpty }.prefix(16))
    }

    /// The longest bank name a message can give; the rest is cut, the same way every time,
    /// so a style always finds the bank it made.
    static let maxBankName = 32

    private static func bankName(_ s: String) -> String {
        String(s.trimmingCharacters(in: .whitespaces).prefix(maxBankName)).trimmingCharacters(in: .whitespaces)
    }

    /// A tone's rig: "rig" by slot, or just the amp of "amp". Knobs that aren't numbers are left out.
    private static func rig(_ tone: [String: Any]) -> [String: RigItem] {
        var out: [String: RigItem] = [:]
        for (slot, value) in tone["rig"] as? [String: Any] ?? [:] {
            guard let item = value as? [String: Any], let gear = item["gear"] as? String else { continue }
            let knobs = (item["knobs"] as? [String: Any] ?? [:]).compactMapValues { v -> Double? in
                guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
                return n.doubleValue
            }
            out[slot] = RigItem(gear: gear, knobs: knobs)
        }
        if out["Amp"] == nil, let amp = tone["amp"] as? [String: Any], let gear = amp["gear"] as? String {
            var knobs: [String: Double] = [:]
            for (name, knob) in [("gain", "Gain"), ("bass", "Bass"), ("mid", "Mid"), ("treble", "Treble"), ("presence", "Pres")] {
                if let n = amp[name] as? NSNumber { knobs[knob] = n.doubleValue }
            }
            out["Amp"] = RigItem(gear: gear, knobs: knobs)
        }
        return out
    }

    /// `on`: what the pedal's switch becomes when the fields don't say; version 1 and the effects turn it on.
    private static func change(_ slot: EffectSlot, _ fields: [String: Any], _ key: String,
                               _ warnings: inout [String], on: Bool?? = .some(true)) -> Change? {
        var change = Change(on: fields["on"] as? Bool ?? (on ?? nil))
        if let name = fields["model"] as? String {
            guard let model = slot.models.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                warnings.append("\(key): \(slot.name) has no model \"\(name)\"; left as it is")
                return nil
            }
            change.model = model.id
        }
        for (name, value) in fields where name != "on" && name != "model" {
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else {
                warnings.append("\(key): \(slot.name) \(name) isn't a number")
                continue
            }
            change.knobs[name] = number.floatValue
        }
        return change
    }

    /// "Classic rock: PC 8 skid18an_clean (Clean, FX Chorus), PC 9 …"
    var summary: String {
        "\(bank.isEmpty ? "no bank" : bank): " + tones.enumerated().map { i, t in
            let on = EffectSlot.allCases.compactMap { slot -> String? in
                guard let c = t.changes[slot], c.on != false else { return nil }
                return c.model.flatMap { slot.model($0)?.name }.map { "\(slot.name) \($0)" } ?? slot.name
            }
            let amp = t.rig["Amp"].map { ", amp \($0.gear)" } ?? ""
            return "PC \(t.program) \(t.key) (\(Self.slots[t.slot])" + (on.isEmpty ? "" : ", " + on.joined(separator: ", ")) + amp + ")"
        }.joined(separator: ", ")
    }
}

/// A version 2 message's effects on the BandBox's pedals: the closest model, the mix kept at
/// most 35 so a wet tone doesn't get louder than its
/// template, and the delay's time from the song's tempo when the gear has none. A tone without
/// a delay or modulation has that pedal off; without a reverb, the template's reverb stays.
enum BandBoxMapping {
    static let maxMix = 35.0

    /// The pedal changes ("FX", "Delay", "Reverb", as version 1's "set") for a tone's "effects".
    static func pedals(_ effects: [String: Any], tempo: Double?) -> [String: Any] {
        func number(_ fields: [String: Any], _ key: String) -> Double? { (fields[key] as? NSNumber)?.doubleValue }
        func mix(_ fields: [String: Any]) -> Double? { number(fields, "mix").map { min(max($0, 0), maxMix).rounded() } }
        var set: [String: Any] = [:]
        if let d = effects["delay"] as? [String: Any] {
            let time = number(d, "time_ms") ?? tempo.map { 60000 / $0 } ?? 400
            var delay: [String: Any] = ["on": true, "model": delayModel(d["kind"] as? String ?? ""),
                                        "Time": min(max(time, 20), 1000).rounded()]
            if let m = mix(d) { delay["Mix"] = m }
            if let f = number(d, "feedback") { delay["Fdbk"] = min(max(f, 0), 100).rounded() }
            set["Delay"] = delay
        } else {
            set["Delay"] = ["on": false]
        }
        if let m = effects["modulation"] as? [String: Any] {
            let kind = m["kind"] as? String ?? ""
            var mod: [String: Any] = ["on": true, "model": modulationModel(kind)]
            if kind == "chorus", let x = mix(m) { mod["Mix"] = x }  // the others have no Mix
            set["FX"] = mod
        } else {
            set["FX"] = ["on": false]
        }
        if let r = effects["reverb"] as? [String: Any] {
            var reverb: [String: Any] = ["on": true]
            if let x = mix(r) { reverb["Mix"] = x }
            set["Reverb"] = reverb
        }
        return set
    }

    /// Whether a template's amp can be switched: only between guitar amps. Going back from Acoustic
    /// Amp and Studio Bass has never been captured, and a template on Bass Amp is for a bass.
    static func canSwitchAmp(from model: UInt16) -> Bool { model & 0xFF == 0x06 && model != 0x0806 }

    /// The BandBox delay for a kind of delay: tape, analog, modulated, digital.
    static func delayModel(_ kind: String) -> String {
        switch kind {
        case "tape": "Echopress 900"
        case "analog": "Analog Echo"
        case "modulated": "Sweep Echo"
        default: "Pure Echo"
        }
    }

    /// The BandBox modulation for a kind: chorus, flanger, phaser, tremolo, vibe.
    static func modulationModel(_ kind: String) -> String {
        switch kind {
        case "flanger": "Jetter Flanger"
        case "phaser": "Green Phaser"
        case "tremolo": "Tremolo"
        case "vibe": "Minivibe"
        default: "Chorus"
        }
    }
}

/// What Stagehand knows of one effect block of a scratch tone. After a model change the
/// speaker picks the new model's defaults, so only the knobs that were set are known.
struct KnownBlock: Equatable, Codable {
    let slot: Int
    var model: UInt16
    var bypassed: Bool
    var params: [UInt8: Float]

    init(slot: Int, model: UInt16, bypassed: Bool, params: [UInt8: Float]) {
        self.slot = slot
        self.model = model
        self.bypassed = bypassed
        self.params = params
    }

    init(_ block: EffectBlock) {
        self.init(slot: block.slot, model: block.model, bypassed: block.bypassed,
                  params: Dictionary(block.params.map { ($0.id, $0.value) }) { a, _ in a })
    }
}

/// How a scratch tone is filled: what it should hold (its template with the song's changes),
/// and the 0x3445 writes that get it there. Edits always go to the tone the channel plays, and
/// a save into another tone copies the playing tone there (protocol-notes.md, Tone actions), so
/// a scratch tone is filled by selecting its template, making the writes from the template's
/// blocks to the target, and saving into the scratch tone; then the template's edits are dropped.
enum ScratchPlan {
    enum Edit: Equatable {
        case model(slot: Int, model: UInt16)
        case param(slot: Int, model: UInt16, param: UInt8, value: Float)
        case bypass(slot: Int, model: UInt16, bypassed: Bool, params: [EffectParam])

        /// The 0x3445 value that makes this edit to tone `tone` on guitar channel `channel`.
        func value(channel: Int, tone: Int) -> [UInt8] {
            let head = [UInt8(channel), UInt8(tone)]
            switch self {
            case let .model(slot, model):
                let op = EffectSlot(rawValue: slot)?.modelOp(model) ?? .model
                return head + [op.rawValue, UInt8(slot)] + BandBoxProtocol.le16(model) + [0xFF, 0x00]
            case let .param(slot, model, param, value):
                return head + [EffectOp.param.rawValue, UInt8(slot)] + BandBoxProtocol.le16(model)
                    + [0xFF, 0x01, param] + BandBoxProtocol.f32(value)
            case let .bypass(slot, model, bypassed, params):
                return head + [EffectOp.bypass.rawValue]
                    + EffectBlock(slot: slot, model: model, bypassed: bypassed, params: params).bytes
            }
        }
    }

    /// What a scratch tone should hold: every block of `template`, with the song tone's changes
    /// to FX, Delay and Reverb. Knobs are found by name on the block's (new) model and kept in
    /// their range; `warnings` gets the ones that aren't there. With `matchAmp`, a tone with a
    /// guitar amp in its rig also gets the amp, cabinet and drive pedal nearest the rig, at the
    /// template's level (GearMatch); `notes` gets what was picked. The pedals a message sets by
    /// name come last, over both.
    static func target(template: ToneDetails, tone: SongTonesRequest.Tone, matchAmp: Bool = false,
                       warnings: inout [String], notes: inout [String]) -> [KnownBlock] {
        let match = matchAmp ? GearMatch.match(template: template, tone: tone) : nil
        if let match { notes.append("\(tone.key): \(match.note)") }
        return template.blocks.map { block in
            var known = match?.blocks[block.slot] ?? KnownBlock(block)
            guard let slot = EffectSlot(rawValue: block.slot), let change = tone.changes[slot] else { return known }
            if let model = change.model, model != known.model {
                known.model = model
                known.params = [:]          // the new model's defaults, unknown until the speaker answers
            }
            if let on = change.on { known.bypassed = !on }
            let specs = slot.model(known.model)?.params ?? []
            for (name, value) in change.knobs.sorted(by: { $0.key < $1.key }) {
                guard let spec = specs.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
                    warnings.append("\(tone.key): \(slot.name) \(slot.model(known.model)?.name ?? "") has no knob \(name)")
                    continue
                }
                known.params[spec.id] = spec.clamp(value)
            }
            return known
        }
    }

    static func target(template: ToneDetails, tone: SongTonesRequest.Tone, matchAmp: Bool = false,
                       warnings: inout [String]) -> [KnownBlock] {
        var notes: [String] = []
        return target(template: template, tone: tone, matchAmp: matchAmp, warnings: &warnings, notes: &notes)
    }

    /// The writes that take a scratch tone from `current` (nil: unknown) to `target`, slot by
    /// slot: a model change first, then the knobs that differ, then the pedal's on/off.
    static func edits(from current: [KnownBlock]?, to target: [KnownBlock]) -> [Edit] {
        target.sorted { $0.slot < $1.slot }.flatMap { t -> [Edit] in
            let now = current?.first { $0.slot == t.slot }
            let newModel = now?.model != t.model || current == nil
            var out: [Edit] = newModel ? [.model(slot: t.slot, model: t.model)] : []
            for (id, value) in t.params.sorted(by: { $0.key < $1.key }) where newModel || now?.params[id] != value {
                out.append(.param(slot: t.slot, model: t.model, param: id, value: value))
            }
            // An amp or a cab keeps its on or off through a change of model, so that stays one write
            let ampOnly = current != nil && (t.slot == EffectSlot.amp.rawValue || t.slot == EffectSlot.cab.rawValue)
            if (newModel && !ampOnly) || now?.bypassed != t.bypassed {
                let params = t.params.sorted { $0.key < $1.key }.map { EffectParam(id: $0.key, value: $0.value) }
                out.append(.bypass(slot: t.slot, model: t.model, bypassed: t.bypassed, params: params))
            }
            return out
        }
    }

    /// What the tone holds after `edits` were made to `current`.
    static func applying(_ edits: [Edit], to current: [KnownBlock]?) -> [KnownBlock] {
        var blocks = Dictionary((current ?? []).map { ($0.slot, $0) }) { a, _ in a }
        for edit in edits {
            switch edit {
            case let .model(slot, model):
                blocks[slot] = KnownBlock(slot: slot, model: model, bypassed: blocks[slot]?.bypassed ?? false, params: [:])
            case let .param(slot, model, param, value):
                blocks[slot, default: KnownBlock(slot: slot, model: model, bypassed: false, params: [:])].params[param] = value
            case let .bypass(slot, model, bypassed, _):
                blocks[slot, default: KnownBlock(slot: slot, model: model, bypassed: bypassed, params: [:])].bypassed = bypassed
            }
        }
        return blocks.values.sorted { $0.slot < $1.slot }
    }
}
