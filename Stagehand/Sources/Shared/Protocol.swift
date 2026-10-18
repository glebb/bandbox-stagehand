import Foundation

// JBL BandBox Trio control protocol (reverse engineered; see protocol-notes.md).
//
// Every message, both directions, little-endian:
//   00 dd | type u16 | fragTotal u8, fragIndex u8 | length u16 | payload
// GET payload:   list of u16 property IDs
// SET payload:   property records
// Replies/events: u16 status + property records
// Property record: id u16 | length u16 | value

enum MessageType: UInt16 {
    case get = 1, set = 2, event = 3, ack = 4
}

struct PropertyRecord {
    let id: UInt16
    let value: [UInt8]
}

enum Property {
    static let modelName: UInt16 = 0x0006
    static let battery: UInt16 = 0x000D
    static let keepAlive: UInt16 = 0x0002
    static let streamVolume: UInt16 = 0x2D42      // channel 4 (USB / Bluetooth audio) volume, 0-32
    static let stemType: UInt16 = 0x3081          // ch type: stem channel 1-2 type (StemType)
    static let stemLevel: UInt16 = 0x3082         // ch VV: stem channel 1-3 volume, 0-32
    static let stemTypeQuery: UInt16 = 0x3083     // SET ch: speaker answers with a stemType event
    static let stemLevelQuery: UInt16 = 0x3084    // SET ch: speaker answers with a stemLevel event
    static let stemAI: UInt16 = 0x3085
    static let karaoke: UInt16 = 0x3080           // 00/01: STEM AI karaoke mode (vocals and others only)
    static let pitchShiftActive: UInt16 = 0x30C0  // 01 while the pitch shift isn't 0 (event only)
    static let pitchShift: UInt16 = 0x30C1        // signed semitones, ff = -1
    static let tuner: UInt16 = 0x3100
    static let tunerReference: UInt16 = 0x3103
    static let tunerFeed: UInt16 = 0x3106
    static let channelQuery: UInt16 = 0x3400      // SET n: speaker answers with a channelInfo event
    static let channelInfo: UInt16 = 0x3401       // n plugged type: what is in channel n; its volume is level (n, type)
    static let pickupQuery: UInt16 = 0x3402       // SET ch: speaker answers with a pickup event
    static let pickup: UInt16 = 0x3403            // ch type: guitar channel ch's pickup type (Pickup)
    static let levelQuery: UInt16 = 0x3405
    static let level: UInt16 = 0x3406
    static let presetLibrary: UInt16 = 0x3440     // GET: all tones (id, category, name); 2 fragments
    static let presetQuery: UInt16 = 0x3441       // SET ch: speaker answers with a preset event
    static let preset: UInt16 = 0x3442            // ch NN: guitar channel ch (1 or 3) plays tone NN from the library
    static let toneDetailsQuery: UInt16 = 0x3443  // SET NN: speaker answers with a toneDetails event
    static let toneDetails: UInt16 = 0x3444       // tone NN's name and effect blocks
    static let effectBlock: UInt16 = 0x3445       // SET ch NN op …: 01 + block replaces a block, 02 slot model ff 00 swaps its model
    static let toneAction: UInt16 = 0x3446        // ch op NN target ff 00: op 04 saves tone NN's edits (target ff = itself), 08 discards them?
    static let presetCategories: UInt16 = 0x344A  // GET: category names
    static let uiMode: UInt16 = 0x3804
}

struct Tone: Identifiable, Hashable {
    let id: Int
    let categoryID: Int
    let name: String
}

/// One effect slot of a tone, as carried in 0x3444 and 0x3445:
/// slot u8 | model u16 | bypass u8 | k u8 | k × (param u8, float32).
struct EffectBlock: Hashable {
    let slot: Int
    let model: UInt16
    var bypassed: Bool
    let paramCount: UInt8
    let params: [UInt8]     // raw, resent unchanged when toggling

    var bytes: [UInt8] {
        [UInt8(slot)] + BandBoxProtocol.le16(model) + [bypassed ? 1 : 0, paramCount] + params
    }
}

struct ToneDetails {
    let id: Int
    let name: String
    var blocks: [EffectBlock]
}

/// The pedals the controller shows, by their effect slot in a tone.
enum Pedal: Int, CaseIterable, Identifiable {
    case compressor = 1, distortion = 2, fx = 5, delay = 6, reverb = 7

    var id: Int { rawValue }
    var name: String {
        switch self {
        case .compressor: "Comp"
        case .distortion: "Dist"
        case .fx: "FX"
        case .delay: "Delay"
        case .reverb: "Reverb"
        }
    }

    /// The models the JBL app offers for this pedal, in its order (model IDs from 0x3444 / 0x3445).
    /// Compressor and reverb have one each; the distortion slot holds the wahs and the drive.
    var models: [PedalModel] {
        switch self {
        case .compressor: [PedalModel(id: 0x01, name: "Compressor")]
        case .distortion: [PedalModel(id: 0x02, name: "Auto-Wah"), PedalModel(id: 0x03, name: "Touch-Wah"),
                           PedalModel(id: 0x04, name: "Precision Drive")]
        case .fx: [PedalModel(id: 0x0E, name: "Echo Phase"), PedalModel(id: 0x0F, name: "Green Phaser"),
                   PedalModel(id: 0x11, name: "Notch Phaser"), PedalModel(id: 0x12, name: "Minivibe"),
                   PedalModel(id: 0x13, name: "Tremolo"), PedalModel(id: 0x0B, name: "Chorus"),
                   PedalModel(id: 0x0C, name: "Retro Shiver"), PedalModel(id: 0x0D, name: "Jetter Flanger"),
                   PedalModel(id: 0x09, name: "Grand Vibrato")]
        case .delay: [PedalModel(id: 0x14, name: "Pure Echo"), PedalModel(id: 0x15, name: "Analog Echo"),
                      PedalModel(id: 0x16, name: "Echopress 900"), PedalModel(id: 0x17, name: "Sweep Echo"),
                      PedalModel(id: 0x18, name: "Sweet Echo")]
        case .reverb: [PedalModel(id: 0x1B, name: "Reverb")]
        }
    }
}

struct PedalModel: Identifiable, Hashable {
    let id: UInt16
    let name: String
}

/// What a channel's switch is set to (channel 3 is always guitar).
enum InputType: UInt8 {
    case mic = 1, guitar = 2, line = 3
}

/// One input channel's state, from 0x3401.
struct ChannelInput: Equatable {
    let plugged: Bool
    let type: InputType?

    var hasGuitar: Bool { plugged && type == .guitar }
}

/// A guitar input's pickup setting, in the order the controller shows them.
enum Pickup: UInt8, CaseIterable, Identifiable {
    case active = 1, passiveHumbucker = 2, singleCoil = 0

    var id: UInt8 { rawValue }
    var name: String {
        switch self {
        case .active: "Active"
        case .passiveHumbucker: "Humbucker"
        case .singleCoil: "Single coil"
        }
    }
}

enum StemType: UInt8, CaseIterable, Identifiable {
    case off = 0, guitar = 1, vocals = 2, drums = 3

    var id: UInt8 { rawValue }
    var name: String {
        switch self {
        case .off: "Off"
        case .guitar: "Guitar"
        case .vocals: "Vocals"
        case .drums: "Drums"
        }
    }
}

/// One sample of the live tuner feed (0x3106). The tuner matches guitar strings, not chromatic notes.
struct TunerReading: Equatable {
    let frequency: Float
    let string: Int         // 1 = high E … 6 = low E
    let cents: Float
    let hasSignal: Bool

    var noteName: String {
        ["", "E", "B", "G", "D", "A", "E"][min(max(string, 0), 6)]
    }
}

struct Message {
    let type: UInt16
    let fragmentTotal: UInt8
    let fragmentIndex: UInt8
    let payload: [UInt8]
}

enum BandBoxProtocol {
    static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }

    static func frame(_ type: MessageType, _ payload: [UInt8]) -> Data {
        Data([0x00, 0xDD] + le16(type.rawValue) + [0x01, 0x00] + le16(UInt16(payload.count)) + payload)
    }

    static func get(_ ids: [UInt16]) -> Data {
        frame(.get, ids.flatMap(le16))
    }

    static func set(_ records: [PropertyRecord]) -> Data {
        frame(.set, records.flatMap { le16($0.id) + le16(UInt16($0.value.count)) + $0.value })
    }

    static func set(_ id: UInt16, _ value: [UInt8]) -> Data {
        set([PropertyRecord(id: id, value: value)])
    }

    static func parse(_ data: Data) -> Message? {
        let b = [UInt8](data)
        guard b.count >= 8, b[0] == 0x00, b[1] == 0xDD else { return nil }
        return Message(type: UInt16(b[2]) | UInt16(b[3]) << 8,
                       fragmentTotal: b[4], fragmentIndex: b[5],
                       payload: Array(b[8...]))
    }

    /// Splits a reply/event payload into its status and property records.
    static func records(_ payload: [UInt8]) -> (status: UInt16, records: [PropertyRecord]) {
        guard payload.count >= 2 else { return (0, []) }
        let status = UInt16(payload[0]) | UInt16(payload[1]) << 8
        var out: [PropertyRecord] = []
        var i = 2
        while i + 4 <= payload.count {
            let id = UInt16(payload[i]) | UInt16(payload[i + 1]) << 8
            let len = Int(UInt16(payload[i + 2]) | UInt16(payload[i + 3]) << 8)
            guard i + 4 + len <= payload.count else { break }
            out.append(PropertyRecord(id: id, value: Array(payload[i + 4 ..< i + 4 + len])))
            i += 4 + len
        }
        return (status, out)
    }

    /// Entries of the form `id cat len name` (tone library, 0x3440).
    static func tones(_ v: [UInt8]) -> [Tone] {
        var out: [Tone] = []
        var i = 0
        while i + 3 <= v.count, i + 3 + Int(v[i + 2]) <= v.count {
            let n = Int(v[i + 2])
            out.append(Tone(id: Int(v[i]), categoryID: Int(v[i + 1]),
                            name: String(decoding: v[i + 3 ..< i + 3 + n], as: UTF8.self)))
            i += 3 + n
        }
        return out
    }

    /// Entries of the form `cat len name` (tone categories, 0x344a).
    static func categories(_ v: [UInt8]) -> [Int: String] {
        var out: [Int: String] = [:]
        var i = 0
        while i + 2 <= v.count, i + 2 + Int(v[i + 1]) <= v.count {
            let n = Int(v[i + 1])
            out[Int(v[i])] = String(decoding: v[i + 2 ..< i + 2 + n], as: UTF8.self)
            i += 2 + n
        }
        return out
    }

    /// One effect block starting at `i`; nil if it runs past the end.
    static func effectBlock(_ v: [UInt8], at i: Int) -> EffectBlock? {
        guard i + 5 <= v.count else { return nil }
        let end = i + 5 + Int(v[i + 4]) * 5
        guard end <= v.count else { return nil }
        return EffectBlock(slot: Int(v[i]), model: UInt16(v[i + 1]) | UInt16(v[i + 2]) << 8,
                           bypassed: v[i + 3] != 0, paramCount: v[i + 4], params: Array(v[i + 5 ..< end]))
    }

    /// 0x3444: `NN cat len name… cnt` then `cnt` effect blocks.
    static func toneDetails(_ v: [UInt8]) -> ToneDetails? {
        guard v.count >= 4, 3 + Int(v[2]) < v.count else { return nil }
        let nameEnd = 3 + Int(v[2])
        var blocks: [EffectBlock] = []
        var i = nameEnd + 1
        for _ in 0 ..< Int(v[nameEnd]) {
            guard let block = effectBlock(v, at: i) else { break }
            blocks.append(block)
            i += block.bytes.count
        }
        return ToneDetails(id: Int(v[0]), name: String(decoding: v[3 ..< nameEnd], as: UTF8.self), blocks: blocks)
    }

    /// 0x3106: frequency f32 | string u8 | offset f32 in half-cents | signal u8.
    static func tunerReading(_ v: [UInt8]) -> TunerReading? {
        guard v.count >= 10 else { return nil }
        func f32(_ at: Int) -> Float {
            Float(bitPattern: UInt32(v[at]) | UInt32(v[at + 1]) << 8 | UInt32(v[at + 2]) << 16 | UInt32(v[at + 3]) << 24)
        }
        return TunerReading(frequency: f32(0), string: Int(v[4]), cents: f32(5) * 2, hasSignal: v[9] == 1)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }
}
