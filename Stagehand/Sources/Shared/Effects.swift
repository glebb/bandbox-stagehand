import Foundation

// The effect catalog: every slot of a tone's chain, the models the JBL app offers for it and
// each model's knobs, from the JBL app captures and pedal pages (protocol-notes.md, Effect models).
// The speaker sends only IDs; names, ranges and the knob order on a page come from here.

/// The eight slots of a tone's signal chain, in the order the signal runs through them.
enum EffectSlot: Int, CaseIterable, Identifiable {
    case gate = 0, compressor, distortion, amp, cab, fx, delay, reverb

    var id: Int { rawValue }
    var name: String {
        switch self {
        case .gate: "Gate"
        case .compressor: "Comp"
        case .distortion: "Dist"
        case .amp: "Amp"
        case .cab: "Cab"
        case .fx: "FX"
        case .delay: "Delay"
        case .reverb: "Reverb"
        }
    }

    /// The models the JBL app offers here, in its order.
    var models: [EffectModel] {
        switch self {
        case .gate: [
            EffectModel(0x00, "Noise Gate", [.knob(0, "Thresh")]),
            EffectModel(0x1C, "Gate", [.knob(0, "Thresh"), .knob(1, "Strength")]),
        ]
        case .compressor: [
            EffectModel(0x01, "Compressor", [.knob(0, "Thresh"), .knob(4, "Output"),
                                             ParamSpec(id: 1, name: "Ratio", range: 1...100, step: 0.1),
                                             .knob(2, "Attack")]),
        ]
        case .distortion: [
            EffectModel(0x02, "Auto-Wah", [.knob(1, "Speed"), .knob(2, "Freq"), .knob(4, "Res"), .knob(0, "Mix")]),
            EffectModel(0x03, "Touch-Wah", [.knob(1, "Sense"), .knob(3, "Res"), .knob(0, "Mix"), .knob(2, "Freq")]),
            EffectModel(0x04, "Precision Drive", [.knob(0, "Drive"), .knob(1, "Bright"), .knob(2, "Level")]),
        ]
        case .amp:
            Self.guitarAmps.enumerated().map { variant, amp in
                EffectModel(UInt16(variant) << 8 | 0x06, amp.name, Self.ampKnobs, category: amp.category)
            } + [
                EffectModel(0x1D, "Acoustic Amp",
                            [ParamSpec(id: 0, name: "Notch", zeroLabel: "Off")] + Self.ampKnobs.dropFirst()),
                EffectModel(0x1E, "Studio Bass", Array(Self.ampKnobs.dropFirst())),
            ]
        case .cab:
            Self.cabs.enumerated().map { variant, name in EffectModel(UInt16(variant) << 8 | 0x08, name, []) }
        case .fx: [
            EffectModel(0x0E, "Echo Phase", [.knob(0, "Speed")]),
            EffectModel(0x0F, "Green Phaser", [.knob(0, "Speed"), .knob(2, "Fdbk"), .small(1, "Depth")]),
            EffectModel(0x11, "Notch Phaser", [.knob(0, "Speed"), .knob(2, "Fdbk"), .small(1, "Depth")]),
            EffectModel(0x12, "Minivibe", [.knob(0, "Speed"), .knob(2, "Fdbk"), .small(1, "Depth")]),
            EffectModel(0x13, "Tremolo", [ParamSpec(id: 1, name: "Shape", range: 0...4,
                                                    choices: ["Sine", "Triangle", "Square", "Saw", "Hump"]),
                                          .knob(2, "Speed"), .small(3, "Depth"), .small(4, "Bias")]),
            EffectModel(0x0B, "Chorus", [.knob(0, "Speed"), .knob(4, "Mix"), .small(1, "Depth")]),
            EffectModel(0x0C, "Retro Shiver", [.knob(0, "Speed"), .knob(1, "Depth")]),
            EffectModel(0x0D, "Jetter Flanger", [.knob(0, "Speed"), .knob(1, "Depth"), .small(2, "Offset"), .small(3, "Fdbk")]),
            EffectModel(0x09, "Grand Vibrato", [.knob(0, "Speed"), .knob(1, "Depth")]),
        ]
        case .delay: [
            EffectModel(0x14, "Pure Echo", Self.delayKnobs),
            EffectModel(0x15, "Analog Echo", Self.delayKnobs),
            EffectModel(0x16, "Echopress 900", Self.delayKnobs),
            // Mix and Time weren't swept on this one; assumed as on the others.
            EffectModel(0x17, "Sweep Echo", [.small(2, "Fdbk"), .small(3, "Speed"), .small(4, "Depth"),
                                             .small(0, "Mix"), Self.delayTime]),
            EffectModel(0x18, "Sweet Echo", Self.delayKnobs),
        ]
        case .reverb: [
            EffectModel(0x1B, "Reverb", [.knob(0, "PreDelay"), .knob(2, "Decay"), .knob(4, "Mix")]),
        ]
        }
    }

    func model(_ id: UInt16) -> EffectModel? { models.first { $0.id == id } }

    /// How the speaker switches this slot to `model` (0x3445): op 03 between the variants of the
    /// amps and cabs (0xNN06 / 0xNN08), op 02 for everything else. Switching from the acoustic
    /// or studio bass amp back to a 0xNN06 amp wasn't captured; op 03 is assumed.
    func modelOp(_ model: UInt16) -> EffectOp {
        (self == .amp || self == .cab) && [0x06, 0x08].contains(model & 0xFF) ? .variant : .model
    }

    // Amps 0x0006 … 0x0806, in the JBL app's order (the variant is the high byte).
    private static let guitarAmps: [(name: String, category: String?)] = [
        ("American Clean", "Clean"), ("Jazz Sound", "Clean"), ("Yellow Tweed", "Low Drive"),
        ("UK Crunch", "Drive"), ("British Lead", "Hi Gain"), ("Vintage Drive", "Drive"),
        ("American Gain Stack", "Hi Gain"), ("US Metal", "Hi Gain"), ("Bass Amp", nil),
    ]
    private static let ampKnobs: [ParamSpec] = [.knob(0, "Drive"), .knob(1, "Bass"), .knob(2, "Mid"),
                                                .knob(3, "Treble"), .knob(4, "Volume")]

    // Cabs 0x0008 … 0x0b08, in the JBL app's order.
    private static let cabs = ["Champion 1x8", "Voks 2x12", "TR65 2x12", "UK 2550 2x12", "BM59 4x10", "Tanger 4x12",
                               "UK 1960 4x12", "6505 4x12", "Mebo 4x12", "M Bass 2x10", "A Bass 8x10", "JC120 2x12"]

    private static let delayTime = ParamSpec(id: 1, name: "Time", range: 20...1000, unit: "ms")
    private static let delayKnobs: [ParamSpec] = [.small(2, "Fdbk"), .small(0, "Mix"), delayTime]
}

/// One model a slot can hold, with its knobs in the order the JBL app's page shows them.
struct EffectModel: Identifiable, Hashable {
    let id: UInt16
    let name: String
    let params: [ParamSpec]
    var category: String?    // the amp's style, shown under its name (Clean, Drive, Hi Gain…)

    init(_ id: UInt16, _ name: String, _ params: [ParamSpec], category: String? = nil) {
        self.id = id
        self.name = name
        self.params = params
        self.category = category
    }

    static func == (a: Self, b: Self) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// One knob of a model: its parameter ID in the effect block and how to show it.
struct ParamSpec: Identifiable {
    let id: UInt8
    let name: String
    var range: ClosedRange<Float> = 0...100
    var step: Float = 1
    var unit: String?
    var small = false              // drawn as a small knob on the JBL app's page
    var choices: [String]?         // a selector rather than a knob: value = index
    var zeroLabel: String?         // shown instead of the minimum, e.g. Notch "Off"

    static func knob(_ id: UInt8, _ name: String) -> Self { ParamSpec(id: id, name: name) }
    static func small(_ id: UInt8, _ name: String) -> Self { ParamSpec(id: id, name: name, small: true) }

    /// Snaps a value to the knob's range and step, as the JBL app sends them.
    func clamp(_ v: Float) -> Float {
        let snapped = ((v - range.lowerBound) / step).rounded() * step + range.lowerBound
        return min(max(snapped, range.lowerBound), range.upperBound)
    }

    func format(_ v: Float) -> String {
        if let choices {
            let i = Int(exactly: v.rounded(.towardZero))
            if let i, choices.indices.contains(i) { return choices[i] }
            return i.map(String.init) ?? "–"
        }
        if let zeroLabel, v <= range.lowerBound { return zeroLabel }
        let number = step < 1 ? String(format: "%.1f", v) : Int(exactly: v.rounded()).map(String.init) ?? "–"
        return unit.map { "\(number) \($0)" } ?? number
    }
}
