/// Which guitar channel an action plays on: the primary one (plain keys) or channel 1 (Shift).
enum ChannelTarget: String, Codable, CaseIterable {
    case primary, channel1

    func channel(_ client: BandBoxClient) -> Int { self == .channel1 ? 1 : client.primaryGuitarChannel }
}

/// What a key (and later a MIDI message) does, as the tones page's buttons do it: select a
/// tone button, or switch a pedal of the channel's current tone.
enum StageAction: Hashable, Codable {
    case tone(slot: Int, ChannelTarget)
    case pedal(Pedal, ChannelTarget)

    /// The keys' order: tone buttons then pedals, of the primary channel then of channel 1.
    static let all: [StageAction] = ChannelTarget.allCases.flatMap { target in
        ToneSlot.all.map { .tone(slot: $0.id, target) } + Pedal.allCases.map { .pedal($0, target) }
    }

    /// "Tone 2", "Dist", with "(CH 1)" for channel 1.
    var label: String {
        switch self {
        case let .tone(slot, target): "Tone \(slot + 1)" + target.suffix
        case let .pedal(pedal, target): pedal.name + target.suffix
        }
    }
}

private extension ChannelTarget {
    var suffix: String { self == .channel1 ? " (CH 1)" : "" }
}

extension BandBoxClient {
    /// Does `action`. A pedal toggles, or is set to `on` when given.
    func perform(_ action: StageAction, assignments: ToneAssignments, on: Bool? = nil) {
        switch action {
        case let .tone(slot, target):
            guard link == .connected else { return }
            let channel = target.channel(self)
            setPreset(assignments.tone(ToneSlot.all[slot], channel: channel), channel: channel)
        case let .pedal(pedal, target):
            let channel = target.channel(self)
            guard let current = isOn(pedal, channel: channel) else { return }
            let on = on ?? !current
            if on != current { setPedal(pedal, on: on, channel: channel) }
        }
    }
}
