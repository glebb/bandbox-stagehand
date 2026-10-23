import Combine
import CoreMIDI

/// One MIDI message bound to an action. `mode` matters only for pedals.
struct MIDIBinding: Hashable, Codable {
    var trigger: MIDITrigger
    var action: StageAction
    var mode: PedalMode = .auto

    /// Any channel. PC 0–3 select the primary guitar channel's tone slots and PC 4–7
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
    private static let enabledKey = "midiEnabled"
    private static let bindingsKey = "midiBindings"

    @Published var enabled = UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(enabled, forKey: Self.enabledKey) }
    }
    /// At most one per action and one per message.
    @Published private(set) var bindings: [MIDIBinding] = MIDIInput.savedBindings() ?? MIDIBinding.defaults {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(bindings), forKey: Self.bindingsKey) }
    }
    @Published private(set) var sources: [String] = []
    @Published private(set) var lastMessage: MIDIMessage?
    @Published private(set) var messageCount = 0
    /// The action that the next message gets bound to (MIDI Learn).
    @Published var learning: StageAction?

    private var midiClient = MIDIClientRef()
    private var port = MIDIPortRef()
    private var connected: Set<MIDIEndpointRef> = []
    private var reader = SwitchReader()
    private let sysex = SysExReaders()
    private weak var client: BandBoxClient?
    private weak var assignments: ToneAssignments?
    /// Song tones (optional): a song tones SysEx has it make the song's tones, and the Program
    /// Changes the message names play them, unless bound to something else. CC 90 picks a bank
    /// by its value (0 = the first), likewise.
    private(set) var filler: ScratchFiller?

    func start(client: BandBoxClient, assignments: ToneAssignments, filler: ScratchFiller) {
        guard midiClient == 0 else { return }
        self.client = client
        self.assignments = assignments
        self.filler = filler
        MainActor.assumeIsolated { filler.start(client: client, assignments: assignments) }
        let status = MIDIClientCreateWithBlock("Stagehand" as CFString, &midiClient) { [weak self] notification in
            guard notification.pointee.messageID == .msgSetupChanged else { return }
            DispatchQueue.main.async { self?.connectSources() }
        }
        guard status == noErr else { return client.record("! MIDI unavailable (\(status))") }
        // Called on CoreMIDI's own thread: parse there, act on the main thread, packet by packet
        // in the order they came (a song's SysEx before the Program Change that plays its tone).
        // The source's endpoint comes as the connection's refCon, so each source has its own SysEx.
        let sysex = self.sysex
        MIDIInputPortCreateWithProtocol(midiClient, "Stagehand in" as CFString, ._1_0, &port) { [weak self] list, refCon in
            let source = Int(bitPattern: refCon)
            let packets = list.unsafeSequence().map { Array($0.words()) }.map { words in
                (sysex: sysex.feed(words, source: source), messages: MIDIMessage.parse(words))
            }
            guard packets.contains(where: { !$0.sysex.isEmpty || !$0.messages.isEmpty }) else { return }
            DispatchQueue.main.async {
                for packet in packets {
                    packet.sysex.forEach { self?.handleSysEx($0) }
                    packet.messages.forEach { self?.handle($0) }
                }
            }
        }
        connectSources()
    }

    private func connectSources() {
        let endpoints = (0..<MIDIGetNumberOfSources()).map(MIDIGetSource).filter { $0 != 0 }
        for source in endpoints where !connected.contains(source) {
            MIDIPortConnectSource(port, source, UnsafeMutableRawPointer(bitPattern: Int(source)))
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

    private static func savedBindings() -> [MIDIBinding]? {
        UserDefaults.standard.data(forKey: bindingsKey).flatMap { try? JSONDecoder().decode([MIDIBinding].self, from: $0) }
    }

    func binding(for action: StageAction) -> MIDIBinding? { bindings.first { $0.action == action } }

    /// Binds `trigger` to `action`, taking it from any other action, keeping the action's mode.
    func bind(_ trigger: MIDITrigger, to action: StageAction) {
        let mode = binding(for: action)?.mode ?? .auto
        bindings.removeAll { $0.action == action || $0.trigger == trigger }
        bindings.append(MIDIBinding(trigger: trigger, action: action, mode: mode))
    }

    func setChannel(_ channel: Int?, for action: StageAction) {
        guard var b = binding(for: action) else { return }
        b.trigger.channel = channel
        bind(b.trigger, to: action)
    }

    func setMode(_ mode: PedalMode, for action: StageAction) {
        if let i = bindings.firstIndex(where: { $0.action == action }) { bindings[i].mode = mode }
    }

    func clear(_ action: StageAction) { bindings.removeAll { $0.action == action } }

    func resetToDefaults() {
        bindings = MIDIBinding.defaults
        learning = nil
    }

    /// A SysEx message: a song tones message (SongTonesRequest) is the only kind Stagehand reads.
    private func handleSysEx(_ bytes: [UInt8]) {
        guard enabled, let request = SongTonesRequest.parse(bytes), let filler else { return }
        let song = request.song.isEmpty ? "a song" : request.song
        guard MainActor.assumeIsolated({ filler.enabled }) else {
            client?.record("MIDI song tones for \(song) ignored: Song tones is off (MIDI settings)")
            return
        }
        client?.record("MIDI song tones for \(song): \(request.summary)")
        request.warnings.forEach { client?.record("! song tones: \($0)") }
        MainActor.assumeIsolated { filler.load(request) }
    }

    private func handle(_ message: MIDIMessage) {
        lastMessage = message
        messageCount += 1
        if let action = learning {
            // A momentary switch's release, coming next, shouldn't press it right away.
            _ = reader.press(message, mode: .auto)
            bind(MIDITrigger(kind: message.kind, number: message.number), to: action)
            learning = nil
            client?.record("MIDI \(message.label) learned for \(action.label)")
            return
        }
        guard enabled, let client, let assignments else { return }
        if message.kind == .program, !bindings.contains(where: { $0.trigger.matches(message) }), let filler,
           let index = MainActor.assumeIsolated({ filler.index(program: message.number) }) {
            client.record("MIDI \(message.label) → song tone \(index + 1)")
            MainActor.assumeIsolated { filler.play(index) }
            return
        }
        if message.kind == .control, message.number == 90, !bindings.contains(where: { $0.trigger.matches(message) }) {
            guard assignments.banks.indices.contains(message.value) else {
                client.record("MIDI \(message.label): no bank \(message.value + 1) (there are \(assignments.banks.count))")
                return
            }
            assignments.selectBank(message.value)
            client.record("MIDI \(message.label) → bank \(assignments.bankName)")
            return
        }
        guard let binding = bindings.first(where: { $0.trigger.matches(message) }),
              let press = reader.press(message, mode: binding.mode) else { return }
        client.record("MIDI \(message.label) → \(binding.action.label)")
        switch press {
        case .toggle: client.perform(binding.action, assignments: assignments)
        case let .set(on): client.perform(binding.action, assignments: assignments, on: on)
        }
    }
}

/// A SysEx assembler per MIDI source, used on CoreMIDI's thread.
private final class SysExReaders {
    private let lock = NSLock()
    private var assemblers: [Int: SysExAssembler] = [:]

    func feed(_ words: [UInt32], source: Int) -> [[UInt8]] {
        lock.lock(); defer { lock.unlock() }
        return assemblers[source, default: SysExAssembler()].feed(words)
    }
}
