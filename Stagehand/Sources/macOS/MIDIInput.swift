import Combine
import CoreMIDI

/// One MIDI message bound to an action. `mode` matters only for pedals.
struct MIDIBinding: Hashable, Codable {
    var trigger: MIDITrigger
    var action: StageAction
    var mode: PedalMode = .auto

    /// Any channel. PC 0–3 select the primary guitar channel's tone buttons and PC 4–7
    /// channel 1's; CC 80–84 switch the primary channel's Comp, Dist, FX, Delay and Reverb
    /// and CC 85–89 channel 1's. CC 80–89 are general-purpose controllers nothing else uses.
    static let defaults: [MIDIBinding] = StageAction.all.enumerated().map { i, action in
        let perChannel = ToneSlot.all.count + Pedal.allCases.count
        let (target, index) = (i / perChannel, i % perChannel)
        let trigger = switch action {
        case .tone: MIDITrigger(kind: .program, number: target * ToneSlot.all.count + index)
        case .pedal: MIDITrigger(kind: .control, number: 80 + target * Pedal.allCases.count + index - ToneSlot.all.count)
        }
        return MIDIBinding(trigger: trigger, action: action)
    }
}

/// Listens to every MIDI source on the Mac (keyboards, footswitch boards, apps' virtual
/// outputs) and does the bound actions, with the app in front or not. Sources that come
/// later are connected as they appear. CoreMIDI needs no permission.
final class MIDIInput: ObservableObject {
    @Published private(set) var sources: [String] = []
    @Published private(set) var lastMessage: MIDIMessage?
    var bindings = MIDIBinding.defaults

    private var midiClient = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: Set<MIDIEndpointRef> = []
    private var reader = SwitchReader()
    private weak var client: BandBoxClient?
    private weak var assignments: ToneAssignments?

    func start(client: BandBoxClient, assignments: ToneAssignments) {
        guard midiClient == 0 else { return }
        self.client = client
        self.assignments = assignments
        let status = MIDIClientCreateWithBlock("Stagehand" as CFString, &midiClient) { [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { self?.connectSources() }
        }
        guard status == noErr else { return client.record("! MIDI unavailable (\(status))") }
        // Called on CoreMIDI's own thread: parse there, act on the main thread.
        MIDIInputPortCreateWithProtocol(midiClient, "Stagehand in" as CFString, ._1_0, &port) { [weak self] list, _ in
            let messages = list.unsafeSequence().flatMap { MIDIMessage.parse($0.words()) }
            guard !messages.isEmpty else { return }
            DispatchQueue.main.async { messages.forEach { self?.handle($0) } }
        }
        connectSources()
    }

    private func connectSources() {
        let endpoints = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter { $0 != 0 }
        for source in endpoints where !connected.contains(source) {
            MIDIPortConnectSource(port, source, nil)
        }
        connected = Set(endpoints)
        let names = endpoints.map(Self.name)
        if names != sources {
            client?.record("MIDI sources: \(names.isEmpty ? "none" : names.joined(separator: ", "))")
            sources = names
        }
    }

    private static func name(_ endpoint: MIDIEndpointRef) -> String {
        var name: Unmanaged<CFString>?
        MIDIObjectGetStringProperty(endpoint, kMIDIPropertyDisplayName, &name)
        return name?.takeRetainedValue() as String? ?? "MIDI source"
    }

    private func handle(_ message: MIDIMessage) {
        lastMessage = message
        guard let client, let assignments,
              let binding = bindings.first(where: { $0.trigger.matches(message) }),
              let press = reader.press(message, mode: binding.mode) else { return }
        client.record("MIDI \(message.label) → \(binding.action.label)")
        switch press {
        case .toggle: client.perform(binding.action, assignments: assignments)
        case let .set(on): client.perform(binding.action, assignments: assignments, on: on)
        }
    }
}
