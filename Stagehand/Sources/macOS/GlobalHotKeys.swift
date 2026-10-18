import Carbon.HIToolbox
import Combine

/// System-wide keys for playing with one hand while another app is in front: 1–4 select the
/// tone buttons, 5–9 switch Comp, Dist, FX, Delay and Reverb, of the primary guitar channel;
/// with Shift, of channel 1. Plain keys, so they're only
/// taken while `enabled` (the Keys switch in the footer); otherwise typing works as usual.
/// Carbon hot keys need no Accessibility permission, and the keys don't reach the app in front.
final class GlobalHotKeys: ObservableObject {
    private static let defaultsKey = "globalHotKeys"
    private static let signature: OSType = 0x4242_5348   // "BBSH"
    private static let digitKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                    kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]

    @Published var enabled = UserDefaults.standard.bool(forKey: defaultsKey) {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.defaultsKey)
            enabled ? register() : unregister()
        }
    }

    private var refs: [EventHotKeyRef] = []
    private var actions: [() -> Void] = []
    private var handler: EventHandlerRef?

    func start(client: BandBoxClient, assignments: ToneAssignments) {
        guard handler == nil else { return }
        // Ids 0–8: plain keys, primary guitar channel; 9–17: Shift, channel 1.
        actions = StageAction.all.map { action in
            { [weak client, weak assignments] in
                if let client, let assignments { client.perform(action, assignments: assignments) }
            }
        }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            var id = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard let context else { return OSStatus(eventNotHandledErr) }
            let keys = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
            if keys.actions.indices.contains(Int(id.id)) { keys.actions[Int(id.id)]() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)

        if enabled { register() }
    }

    private func register() {
        guard handler != nil, refs.isEmpty else { return }
        for (row, modifiers) in [0, shiftKey].enumerated() {
            for (i, key) in Self.digitKeys.enumerated() {
                var ref: EventHotKeyRef?
                let id = EventHotKeyID(signature: Self.signature, id: UInt32(row * Self.digitKeys.count + i))
                // Fails if another app already holds the key; the in-app keys still work then.
                if RegisterEventHotKey(UInt32(key), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                    refs.append(ref)
                }
            }
        }
    }

    private func unregister() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }

    deinit {
        unregister()
        if let handler { RemoveEventHandler(handler) }
    }
}
