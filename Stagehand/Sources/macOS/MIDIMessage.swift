import Foundation

/// The MIDI messages Stagehand acts on: Program Change, Control Change and Note On.
struct MIDIMessage: Equatable {
    enum Kind: String, Codable { case program, control, note }

    let kind: Kind
    let channel: Int   // 0–15
    let number: Int    // program, controller or note
    let value: Int     // CC value or velocity; 127 for a program change

    /// Parses MIDI 1.0 universal MIDI packets (as CoreMIDI delivers them for the 1.0
    /// protocol), skipping every other message and Note On with velocity 0 (a Note Off).
    static func parse(_ words: some Sequence<UInt32>) -> [MIDIMessage] {
        var messages: [MIDIMessage] = []
        var remaining = 0   // words left of a message that isn't a MIDI 1.0 channel voice one
        for word in words {
            if remaining > 0 { remaining -= 1; continue }
            let type = Int(word >> 28)
            remaining = wordCount[type] - 1
            guard type == 0x2 else { continue }
            let status = Int(word >> 16) & 0xF0
            let channel = Int(word >> 16) & 0x0F
            let data1 = Int(word >> 8) & 0x7F
            let data2 = Int(word) & 0x7F
            switch status {
            case 0xC0: messages.append(MIDIMessage(kind: .program, channel: channel, number: data1, value: 127))
            case 0xB0: messages.append(MIDIMessage(kind: .control, channel: channel, number: data1, value: data2))
            case 0x90 where data2 > 0: messages.append(MIDIMessage(kind: .note, channel: channel, number: data1, value: data2))
            default: break
            }
        }
        return messages
    }

    /// Words in a universal MIDI packet, by its message type (the top 4 bits).
    private static let wordCount = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    /// As the log and the MIDI sheet show it: "PC 2", "CC 81 = 127", "Note 60"; channels 1–16.
    var label: String {
        switch kind {
        case .program: "PC \(number) · ch \(channel + 1)"
        case .control: "CC \(number) = \(value) · ch \(channel + 1)"
        case .note: "Note \(number) · ch \(channel + 1)"
        }
    }
}

/// Puts SysEx messages back together from MIDI 1.0 universal MIDI packets (type 3: up to 6
/// bytes each, marked complete, start, continue or end), which may span several packet lists.
/// One per source, so two sources' messages aren't mixed.
struct SysExAssembler {
    /// Longer messages are dropped: Stagehand's own are a few kilobytes.
    static let maxLength = 16_384

    private var buffer: [UInt8]?

    /// The messages that `words` complete, as the bytes between F0 and F7.
    mutating func feed(_ words: some Sequence<UInt32>) -> [[UInt8]] {
        var done: [[UInt8]] = []
        var iterator = words.makeIterator()
        while let word = iterator.next() {
            let type = Int(word >> 28)
            guard type == 0x3 else {
                for _ in 1 ..< Self.wordCount[type] { _ = iterator.next() }
                continue
            }
            guard let second = iterator.next() else { break }
            let status = word >> 20 & 0xF, count = min(Int(word >> 16 & 0xF), 6)
            let bytes = [word >> 8, word, second >> 24, second >> 16, second >> 8, second].prefix(count).map { UInt8($0 & 0x7F) }
            switch status {
            case 0: done.append(bytes); buffer = nil                   // complete in one
            case 1: buffer = bytes                                     // start
            case 2: buffer? += bytes                                   // continue
            case 3: if let b = buffer { done.append(b + bytes) }; buffer = nil   // end
            default: buffer = nil
            }
            if (buffer?.count ?? 0) > Self.maxLength { buffer = nil }
        }
        return done
    }

    private static let wordCount = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]
}

/// What a MIDI binding listens to: a program, controller or note, on one channel or any.
struct MIDITrigger: Hashable, Codable {
    let kind: MIDIMessage.Kind
    let number: Int
    var channel: Int?   // 0–15; nil = any channel

    func matches(_ m: MIDIMessage) -> Bool {
        m.kind == kind && m.number == number && (channel == nil || channel == m.channel)
    }

    /// "PC 2", "CC 81 · ch 3", "Note 60".
    var label: String {
        let name = switch kind {
        case .program: "PC \(number)"
        case .control: "CC \(number)"
        case .note: "Note \(number)"
        }
        return channel.map { "\(name) · ch \($0 + 1)" } ?? name
    }
}

/// How a pedal's binding reads a controller's value.
enum PedalMode: String, Codable, CaseIterable {
    /// Every press toggles, whether the switch is momentary (127, then 0 on letting go) or
    /// latching (127 on one press, 0 on the next).
    case auto
    /// 64 and up is on, below is off: the pedal follows a latching switch and can't drift.
    case follow
}

/// Turns incoming messages into presses, telling a momentary switch letting go apart from
/// a latching switch's next press. Both send 64 or more, then less: a momentary switch
/// within a press's length, a latching one at the next press. Until a controller has shown
/// which it is, a value below 64 within a second of a high one is taken as a release.
struct SwitchReader {
    enum Press: Equatable { case toggle, set(Bool) }

    /// High to low faster than this: a press and release, so the switch is momentary.
    static let pressLength: TimeInterval = 0.5
    /// High to low slower than this: two presses, so the switch is latching.
    static let latchingGap: TimeInterval = 2
    static let releaseWindow: TimeInterval = 1

    private var lastHigh: [String: Date] = [:]
    private var momentary: [String: Bool] = [:]   // learned per controller

    /// The press `message` makes in `mode`, or nil when it's a momentary switch's release.
    mutating func press(_ message: MIDIMessage, mode: PedalMode, at now: Date = Date()) -> Press? {
        guard message.kind == .control else { return .toggle }
        let high = message.value >= 64
        if mode == .follow { return .set(high) }
        let key = "\(message.channel).\(message.number)"
        if high {
            lastHigh[key] = now
            return .toggle
        }
        let gap = lastHigh.removeValue(forKey: key).map { now.timeIntervalSince($0) }
        if let gap, gap < Self.pressLength { momentary[key] = true }
        if let gap, gap > Self.latchingGap { momentary[key] = false }
        let release = momentary[key] ?? (gap.map { $0 < Self.releaseWindow } ?? false)
        return release ? nil : .toggle
    }
}
