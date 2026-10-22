import Foundation

// Song-made tones for Rocksmith (rs-mac-companion's rig-plan.md). While a song loads, the
// companion sends one SysEx: manufacturer 0x7D, then a JSON text naming each of the song's
// tones, in the order the song first plays them:
//
//   {"v": 1, "kind": "song-tones", "song": "18 And Life", "artist": "Skid Row", "rig": "Classic rock",
//    "tones": [{"program": 8, "key": "skid18an_clean", "base": "Clean",
//               "set": {"FX": {"on": true, "model": "Chorus", "Mix": 35}, "Delay": {"on": false},
//                       "Reverb": {"on": true, "Mix": 25}}}, ...]}
//
// Tone i becomes scratch tone i, which PC 8 + i plays. Each one is a copy of the tone button
// named by "base" (its template) with only the FX, Delay and Reverb pedals changed, so it keeps
// the template's level. Everything else in "set" is refused.

/// The companion's message, checked against the pedals and models Stagehand knows.
struct SongTonesRequest: Equatable {
    static let manufacturer: UInt8 = 0x7D
    static let firstProgram = 8
    static let maxTones = 5           // Rocksmith's Base and A–D
    /// The tone buttons by the names the companion uses for them, in ToneSlot order.
    static let buttons = ["Clean", "Crunch", "Heavy", "Lead"]
    /// The only pedals a song may change: the others set the tone's level.
    static let pedals: [String: EffectSlot] = ["FX": .fx, "Delay": .delay, "Reverb": .reverb]

    struct Tone: Equatable {
        let key: String
        let button: Int                     // the template: index into ToneSlot.all
        let changes: [EffectSlot: Change]
    }

    /// What a song does to one pedal: on or off, perhaps another model, knobs by name.
    struct Change: Equatable {
        var on: Bool
        var model: UInt16?                  // nil: the template's model
        var knobs: [String: Float] = [:]
    }

    let song: String
    let artist: String
    let rig: String
    let tones: [Tone]
    /// What was refused or guessed, for the log.
    let warnings: [String]

    /// The request in a SysEx message's bytes (between F0 and F7), or nil when the message isn't
    /// one: another manufacturer, not JSON, another kind or version.
    static func parse(_ sysex: [UInt8]) -> SongTonesRequest? {
        guard sysex.first == manufacturer,
              let json = try? JSONSerialization.jsonObject(with: Data(sysex.dropFirst())) as? [String: Any],
              json["kind"] as? String == "song-tones", json["v"] as? Int == 1,
              let list = json["tones"] as? [[String: Any]] else { return nil }
        var warnings: [String] = []
        if list.count > maxTones { warnings.append("\(list.count) tones, only the first \(maxTones) are made") }
        let tones = list.prefix(maxTones).enumerated().map { i, t in
            let key = t["key"] as? String ?? "tone \(i + 1)"
            if let program = t["program"] as? Int, program != firstProgram + i {
                warnings.append("\(key): program \(program), but scratch tone \(i + 1) plays on PC \(firstProgram + i)")
            }
            let base = t["base"] as? String ?? ""
            let button = buttons.firstIndex { $0.caseInsensitiveCompare(base) == .orderedSame } ?? {
                warnings.append("\(key): no tone button \"\(base)\", using \(buttons[0])")
                return 0
            }()
            var changes: [EffectSlot: Change] = [:]
            for (name, value) in t["set"] as? [String: Any] ?? [:] {
                guard let slot = pedals[name] else {
                    warnings.append("\(key): \(name) can't be changed, only FX, Delay and Reverb")
                    continue
                }
                guard let fields = value as? [String: Any], let change = change(slot, fields, key, &warnings) else { continue }
                changes[slot] = change
            }
            return Tone(key: key, button: button, changes: changes)
        }
        return SongTonesRequest(song: json["song"] as? String ?? "", artist: json["artist"] as? String ?? "",
                                rig: json["rig"] as? String ?? "", tones: tones, warnings: warnings)
    }

    private static func change(_ slot: EffectSlot, _ fields: [String: Any], _ key: String,
                               _ warnings: inout [String]) -> Change? {
        var change = Change(on: fields["on"] as? Bool ?? true)
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

    /// "Classic rock: 1 skid18an_clean (Clean, FX Chorus), 2 …"
    var summary: String {
        "\(rig.isEmpty ? "no rig" : rig): " + tones.enumerated().map { i, t in
            let on = EffectSlot.allCases.compactMap { slot -> String? in
                guard let c = t.changes[slot], c.on else { return nil }
                return c.model.flatMap { slot.model($0)?.name }.map { "\(slot.name) \($0)" } ?? slot.name
            }
            return "\(i + 1) \(t.key) (\(Self.buttons[t.button])" + (on.isEmpty ? "" : ", " + on.joined(separator: ", ")) + ")"
        }.joined(separator: ", ")
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
/// and the 0x3445 writes that get it there from what it holds now.
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
    /// their range; `warnings` gets the ones that aren't there.
    static func target(template: ToneDetails, tone: SongTonesRequest.Tone, warnings: inout [String]) -> [KnownBlock] {
        template.blocks.map { block in
            var known = KnownBlock(block)
            guard let slot = EffectSlot(rawValue: block.slot), let change = tone.changes[slot] else { return known }
            if let model = change.model, model != block.model {
                known.model = model
                known.params = [:]          // the new model's defaults, unknown until the speaker answers
            }
            known.bypassed = !change.on
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
            if newModel || now?.bypassed != t.bypassed {
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
