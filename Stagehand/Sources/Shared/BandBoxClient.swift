import CoreBluetooth
import Foundation

/// Finds the BandBox Trio over BLE, keeps a connection to its command channel,
/// and exposes the speaker's state plus the controls we know how to send.
///
/// The speaker advertises no name or data and rotates its address every few minutes,
/// so it's found by probing nearby silent devices for the excelpoint command service.
/// Only one control client is allowed: if the JBL app is connected, we get kicked.
final class BandBoxClient: NSObject, ObservableObject {
    enum Link: Equatable {
        case bluetoothOff, unauthorized, searching, connecting, connected
        case offline   // the user stopped connecting; connect() starts again
    }

    @Published private(set) var link: Link = .searching
    @Published private(set) var deviceName: String?
    @Published private(set) var battery: Int?
    /// On the wall power: 0x000D's top bit (the rest is the level).
    @Published private(set) var externalPower = false
    /// Guitar channel (1 or 3) → its current tone id; each guitar input has its own tone.
    @Published private(set) var presets: [Int: Int] = [:]
    @Published private(set) var tones: [Tone] = []
    @Published private(set) var categories: [Int: String] = [:]
    @Published private(set) var stemAI: Bool?
    @Published private(set) var pickups: [Int: Pickup] = [:]   // guitar channel → pickup type
    @Published private(set) var tunerOn = false
    @Published private(set) var tuner: TunerReading?
    @Published private(set) var tunerReference: Double?
    /// Guitar channel → the effect blocks of its current tone, with that channel's unsaved edits.
    @Published private(set) var toneDetails: [Int: ToneDetails] = [:]
    /// Guitar channel → its current tone as saved on the speaker. 0x3444 always answers with the
    /// saved tone, so the edits exist only in toneDetails (and in the speaker, until saved).
    @Published private(set) var savedDetails: [Int: ToneDetails] = [:]
    /// The tone the last save as made, and the channel it was saved from; it plays there now.
    @Published private(set) var createdTone: CreatedTone?
    /// Channel 1–3 → what is plugged into it, from channelInfo events.
    @Published private(set) var inputs: [Int: ChannelInput] = [:]
    /// Level table (0x3406) keyed by `a << 8 | b`; master volume is key 0.
    @Published private(set) var levels: [UInt16: Int] = [:]
    /// Channel 4 is the USB / Bluetooth audio; its volume is its own property, not in the level table.
    @Published private(set) var streamVolume: Int?
    /// Channel n's volume (n = 1-3) is level (n, channelKeys[n]), the key being its input type;
    /// learned from channelInfo events.
    @Published private(set) var channelKeys: [Int: UInt8] = [3: 0x02, 2: 0x03]
    @Published private(set) var stemTypes: [Int: StemType] = [:]   // stem channels 1-2
    @Published private(set) var stemLevels: [Int: Int] = [:]       // stem channels 1-3 (3 = Others)
    @Published private(set) var log: [String] = []
    /// The user tones Stagehand fills for Rocksmith songs (ScratchFiller), scratch tone 1 first.
    /// They are left out of the tone menus.
    @Published var scratchTones: [Int] = UserDefaults.standard.array(forKey: "scratchTones") as? [Int] ?? [] {
        didSet { UserDefaults.standard.set(scratchTones, forKey: "scratchTones") }
    }
    /// Called with every record the speaker sends, after it is applied (ScratchFiller waits on them).
    var recordObservers: [UUID: (PropertyRecord) -> Void] = [:]

    static let levelRange = 0...32       // the volume knob has 32 clicks: 0 to 32
    static let channels = 1...4
    static let stemChannels = 1...3
    static let guitarChannels = [1, 3]   // the inputs with tones, pedals and a pickup setting

    /// The guitar channels with a guitar plugged in, or channel 3 alone when there's none.
    var activeGuitarChannels: [Int] {
        let plugged = Self.guitarChannels.filter { inputs[$0]?.hasGuitar == true }
        return plugged.isEmpty ? [3] : plugged
    }

    /// The channel plain keys 1–9 control: channel 3, unless the only guitar is in channel 1.
    var primaryGuitarChannel: Int { activeGuitarChannels.contains(3) ? 3 : activeGuitarChannels[0] }

    private static let commandService = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0000")
    private static let notifyChar = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0001")
    private static let writeChar = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0002")

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var confirmed = false
    private var candidates: [CBPeripheral] = []
    private var rejected = Set<UUID>()
    private var writeQueue: [(data: Data, key: String?)] = []
    private var writeInFlight = false
    private var fragments: [UInt16: [UInt8]] = [:]
    private var rescanTimer: Timer?
    private var stopped = false   // disconnect() was called: don't search until connect()
    private var tunerKeepAlive: Timer?

    override init() {
        super.init()
        setvbuf(stdout, nil, _IOLBF, 0)
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: Controls

    /// The leading byte is the guitar channel; each has its own current tone.
    func setPreset(_ toneID: Int, channel: Int) {
        let name = tones.first { $0.id == toneID }?.name ?? "#\(toneID)"
        send(BandBoxProtocol.set(Property.preset, [UInt8(channel), UInt8(toneID)]), "channel \(channel) preset \(name)")
    }

    func setPickup(_ type: Pickup, channel: Int) {
        pickups[channel] = type
        send(BandBoxProtocol.set(Property.pickup, [UInt8(channel), type.rawValue]), "channel \(channel) pickup \(type.name)")
    }

    func setStemAI(_ on: Bool) {
        send(BandBoxProtocol.set(Property.stemAI, [on ? 1 : 0]), "STEM AI \(on ? "on" : "off")")
    }

    /// Mirrors the JBL app: tuner on, then UI mode 01 02; reverse order to turn off.
    /// A tuner turned on over Bluetooth switches itself off after ~11 s, so while it's on
    /// we repeat the tuner-on SET every 5 s; the speaker keeps it on as long as those arrive.
    func setTuner(_ on: Bool) {
        tunerKeepAlive?.invalidate()
        tunerKeepAlive = nil
        if on {
            send(BandBoxProtocol.set(Property.tuner, [1]), "tuner on")
            send(BandBoxProtocol.set(Property.uiMode, [1, 2]))
            tunerKeepAlive = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
                self?.send(BandBoxProtocol.set(Property.tuner, [1]))
            }
        } else {
            send(BandBoxProtocol.set(Property.uiMode, [1, 0]))
            send(BandBoxProtocol.set(Property.tuner, [0]), "tuner off")
        }
    }

    // MARK: Tone editing
    // Edits go to the tone the channel is playing (0x3445) and last until the tone changes,
    // unless saved (0x3446). The speaker can't report them: 0x3444 returns the saved tone.

    func block(_ slot: EffectSlot, channel: Int) -> EffectBlock? { toneDetails[channel]?.block(slot) }

    /// Whether the channel's tone has edits that aren't saved on the speaker.
    func isEdited(channel: Int) -> Bool {
        guard let details = toneDetails[channel] else { return false }
        return details != savedDetails[channel]
    }

    func isOn(_ pedal: Pedal, channel: Int) -> Bool? { block(pedal.slot, channel: channel).map { !$0.bypassed } }

    func setPedal(_ pedal: Pedal, on: Bool, channel: Int) { setBypass(pedal.slot, on: on, channel: channel) }

    /// Resends the slot's effect block from the channel's current tone with the bypass byte flipped.
    func setBypass(_ slot: EffectSlot, on: Bool, channel: Int) {
        guard var details = editableDetails(channel),
              let i = details.blocks.firstIndex(where: { $0.slot == slot.rawValue }) else { return }
        details.blocks[i].bypassed = !on
        toneDetails[channel] = details
        sendEdit(channel, details, .bypass, details.blocks[i].bytes, "channel \(channel) \(slot.name) \(on ? "on" : "off")")
    }

    func model(_ pedal: Pedal, channel: Int) -> UInt16? { block(pedal.slot, channel: channel)?.model }

    func setModel(_ pedal: Pedal, _ model: EffectModel, channel: Int) { setModel(pedal.slot, model, channel: channel) }

    /// Swaps the slot's model in the current tone; the speaker answers with the new block
    /// and its default parameters, keeping the on/off state.
    func setModel(_ slot: EffectSlot, _ model: EffectModel, channel: Int) {
        guard let details = editableDetails(channel) else { return }
        sendEdit(channel, details, slot.modelOp(model.id), [UInt8(slot.rawValue)] + BandBoxProtocol.le16(model.id) + [0xFF, 0x00],
                 "channel \(channel) \(slot.name) model \(model.name)")
    }

    /// Sets one knob of the channel's current tone, snapped to the knob's range and step.
    /// Not logged: a drag sends one every write.
    func setParam(_ slot: EffectSlot, _ param: UInt8, to value: Float, channel: Int) {
        guard var details = editableDetails(channel),
              let i = details.blocks.firstIndex(where: { $0.slot == slot.rawValue }),
              let p = details.blocks[i].params.firstIndex(where: { $0.id == param }) else { return }
        let block = details.blocks[i]
        let value = slot.model(block.model)?.params.first { $0.id == param }?.clamp(value) ?? value
        details.blocks[i].params[p].value = value
        toneDetails[channel] = details
        sendEdit(channel, details, .param,
                 [UInt8(slot.rawValue)] + BandBoxProtocol.le16(block.model) + [0xFF, 0x01, param] + BandBoxProtocol.f32(value),
                 nil, coalesce: "param \(channel) \(slot.rawValue) \(param)")
    }

    /// Saves the channel's edits into its current tone on the speaker, as the JBL app does.
    /// Without it, the edits are lost when the speaker changes tone.
    func saveTone(channel: Int) {
        guard let details = editableDetails(channel) else { return }
        send(BandBoxProtocol.toneAction(.save, channel: channel, tone: details.id), "channel \(channel) save tone \(details.name)")
    }

    /// Saves the channel's current tone with its edits as a new user tone; the speaker answers
    /// with its ID, and the channel then plays it (see createdTone). The tone itself keeps its
    /// saved settings. The category is an ID from `categories`.
    func saveToneAs(_ name: String, category: Int, channel: Int) {
        guard let details = editableDetails(channel) else { return }
        send(BandBoxProtocol.toneAction(.saveAs, channel: channel, tone: details.id, category: UInt8(category), name: name),
             "channel \(channel) save \(details.name) as \(name)")
    }

    /// Drops the channel's edits; the speaker goes back to the saved tone.
    func discardEdits(channel: Int) {
        guard let details = editableDetails(channel) else { return }
        send(BandBoxProtocol.toneAction(.discard, channel: channel, tone: details.id), "channel \(channel) discard edits")
    }

    func renameTone(_ toneID: Int, to name: String, channel: Int) {
        send(BandBoxProtocol.toneAction(.rename, channel: channel, tone: toneID, target: UInt8(toneID), name: name),
             "rename \(toneName(toneID)) to \(name)")
    }

    func deleteTone(_ toneID: Int, channel: Int) {
        send(BandBoxProtocol.toneAction(.delete, channel: channel, tone: toneID), "delete \(toneName(toneID))")
    }

    /// Puts a factory tone back to its factory settings.
    func resetTone(_ toneID: Int, channel: Int) {
        send(BandBoxProtocol.toneAction(.reset, channel: channel, tone: toneID), "reset \(toneName(toneID)) to factory")
    }

    /// The channel's tone, if it's the one playing: edits only apply to that.
    private func editableDetails(_ channel: Int) -> ToneDetails? {
        guard let details = toneDetails[channel], details.id == presets[channel] else { return nil }
        return details
    }

    private func sendEdit(_ channel: Int, _ details: ToneDetails, _ op: EffectOp, _ rest: [UInt8], _ label: String?,
                          coalesce key: String? = nil) {
        send(BandBoxProtocol.set(Property.effectBlock, [UInt8(channel), UInt8(details.id), op.rawValue] + rest), label, coalesce: key)
    }

    /// Queues a message as it is, after the writes already queued (for ScratchFiller).
    func sendRaw(_ data: Data, _ label: String? = nil) { send(data, label) }

    private func toneName(_ id: Int) -> String { tones.first { $0.id == id }?.name ?? "#\(id)" }

    var masterVolume: Int? { levels[0] }

    static let streamChannel = 4

    func channelVolume(_ channel: Int) -> Int? {
        if channel == Self.streamChannel { return streamVolume }
        return channelKeys[channel].flatMap { levels[UInt16(channel) << 8 | UInt16($0)] }
    }

    func changeMasterVolume(by step: Int) {
        changeLevel(a: 0, b: 0, by: step, label: "master")
    }

    func changeChannelVolume(_ channel: Int, by step: Int) {
        if channel == Self.streamChannel {
            guard let v = streamVolume else { return }
            let target = Self.clampLevel(v + step)
            guard target != v else { return }
            streamVolume = target
            send(BandBoxProtocol.set(Property.streamVolume, [UInt8(target)]), "channel 4 volume \(target)")
            return
        }
        guard let k = channelKeys[channel] else { return }
        changeLevel(a: UInt8(channel), b: k, by: step, label: "channel \(channel)")
    }

    /// Updates the level right away so quick repeated taps add up; the speaker's event confirms it.
    private func changeLevel(a: UInt8, b: UInt8, by step: Int, label: String) {
        let key = UInt16(a) << 8 | UInt16(b)
        guard let v = levels[key] else { return }
        let target = Self.clampLevel(v + step)
        guard target != v else { return }
        levels[key] = target
        send(BandBoxProtocol.set(Property.level, [a, b, UInt8(target)]), "\(label) volume \(target)")
    }

    /// A type can be on only one stem channel, so like the JBL app, clear the other channel first.
    func setStemType(_ channel: Int, _ type: StemType) {
        guard (1...2).contains(channel) else { return }
        let other = 3 - channel
        var records: [PropertyRecord] = []
        if type != .off, stemTypes[other] == type {
            stemTypes[other] = .off
            records.append(PropertyRecord(id: Property.stemType, value: [UInt8(other), StemType.off.rawValue]))
        }
        stemTypes[channel] = type
        records.append(PropertyRecord(id: Property.stemType, value: [UInt8(channel), type.rawValue]))
        send(BandBoxProtocol.set(records), "stem \(channel) \(type.name)")
    }

    func changeStemVolume(_ channel: Int, by step: Int) {
        guard let v = stemLevels[channel] else { return }
        let target = Self.clampLevel(v + step)
        guard target != v else { return }
        stemLevels[channel] = target
        send(BandBoxProtocol.set(Property.stemLevel, [UInt8(channel), UInt8(target)] + [UInt8](repeating: 0, count: 7)),
             "stem \(channel) volume \(target)")
    }

    static func clampLevel(_ v: Int) -> Int { min(max(v, levelRange.lowerBound), levelRange.upperBound) }

    /// Levels as the 0–100% the controller shows.
    static func percent(_ level: Int) -> Int { Int((Double(level) * 100 / Double(levelRange.upperBound)).rounded()) }

    // MARK: Sending

    /// Queues a write. A write with a `coalesce` key replaces a queued one with the same key, so
    /// a knob being dragged sends its latest value once the previous write is done.
    private func send(_ data: Data, _ label: String? = nil, coalesce key: String? = nil) {
        guard link == .connected else { return }
        if let key, let i = writeQueue.firstIndex(where: { $0.key == key }) {
            writeQueue[i].data = data
            return
        }
        if let label { record("→ \(label)") }
        writeQueue.append((data, key))
        pumpWrites()
    }

    private func pumpWrites() {
        guard !writeInFlight, !writeQueue.isEmpty,
              let p = peripheral, let w = writeCharacteristic else { return }
        writeInFlight = true
        p.writeValue(writeQueue.removeFirst().data, for: w, type: .withResponse)
    }

    // MARK: Receiving

    private func handle(_ data: Data) {
        guard let msg = BandBoxProtocol.parse(data) else {
            record("? unframed \(BandBoxProtocol.hex([UInt8](data)))")
            return
        }
        var payload = msg.payload
        if msg.fragmentTotal > 1 {
            // A first fragment starts over, so a message cut off earlier isn't glued to this one.
            if msg.fragmentIndex == 0 { fragments[msg.type] = nil }
            fragments[msg.type, default: []] += payload
            guard msg.fragmentIndex + 1 == msg.fragmentTotal else { return }
            payload = fragments.removeValue(forKey: msg.type) ?? payload
        }
        let (status, records) = BandBoxProtocol.records(payload)
        if status != 0 {
            record("! speaker returned status \(String(format: "0x%04x", status)) for type \(msg.type)")
        }
        for r in records {
            apply(r)
            for observe in recordObservers.values { observe(r) }
        }
    }

    private func apply(_ r: PropertyRecord) {
        switch r.id {
        case Property.preset where r.value.count >= 2:
            // ch NN; the speaker also sends these on its own, e.g. for its preset button.
            let channel = Int(r.value[0])
            presets[channel] = Int(r.value[1])
            if toneDetails[channel]?.id != presets[channel] {
                send(BandBoxProtocol.set(Property.toneDetailsQuery, [r.value[1]]))
            }
        case Property.toneDetails:
            // The query and its answer name only the tone, so it goes to every channel playing it.
            // It's the saved tone: a channel's unsaved edits to it stay.
            if let details = BandBoxProtocol.toneDetails(r.value) {
                for channel in Self.guitarChannels where presets[channel] == details.id {
                    if !isEdited(channel: channel) || toneDetails[channel]?.id != details.id {
                        toneDetails[channel] = details
                    } else {
                        toneDetails[channel]?.name = details.name   // after a rename
                    }
                    savedDetails[channel] = details
                }
                record("← tone \(details.name): \(details.blocks.count) effect blocks")
                return
            }
        case Property.effectBlock where r.value.count >= 7:
            // Echoes of our edits, ch NN op slot …
            let channel = Int(r.value[0])
            let op = EffectOp(rawValue: r.value[2])
            if op == .param { return }  // echoed as sent, already applied; stale during a drag, and many
            guard var details = toneDetails[channel], details.id == Int(r.value[1]),
                  let i = details.blocks.firstIndex(where: { $0.slot == Int(r.value[3]) }) else { break }
            switch op {
            case .block:
                // ch NN 00 slot model ff k params…: a new model with its default parameters.
                if var block = BandBoxProtocol.effectBlock(r.value, at: 3) {
                    block.bypassed = r.value[6] == 0xFF ? details.blocks[i].bypassed : r.value[6] != 0
                    details.blocks[i] = block
                }
            case .bypass where r.value[6] != 0xFF:
                // ch NN 01 slot ff ff bypass 00: the speaker confirming a bypass change.
                details.blocks[i].bypassed = r.value[6] != 0
            default:
                break
            }
            toneDetails[channel] = details
        case Property.toneAction where r.value.count >= 4:
            toneActionDone(channel: Int(r.value[0]), ToneAction(rawValue: r.value[1]), tone: Int(r.value[2]), target: Int(r.value[3]),
                           name: String(decoding: r.value.dropFirst(6), as: UTF8.self))
        case Property.channelInfo where r.value.count >= 3:
            // n plugged type: the input type also keys the channel's volume, (n, type).
            let channel = Int(r.value[0])
            inputs[channel] = ChannelInput(plugged: r.value[1] == 1, type: InputType(rawValue: r.value[2]))
            if channelKeys[channel] != r.value[2] {
                channelKeys[channel] = r.value[2]
                send(BandBoxProtocol.set(Property.levelQuery, [r.value[0], r.value[2]]))
            }
        case Property.pickup where r.value.count >= 2:
            pickups[Int(r.value[0])] = Pickup(rawValue: r.value[1])
        case Property.streamVolume where !r.value.isEmpty:
            streamVolume = Int(r.value[0])
        case Property.stemType where r.value.count >= 2:
            stemTypes[Int(r.value[0])] = StemType(rawValue: r.value[1]) ?? .off
        case Property.stemLevel where r.value.count >= 2:
            stemLevels[Int(r.value[0])] = Int(r.value[1])
        case Property.presetLibrary:
            tones = BandBoxProtocol.tones(r.value)
            record("← tone library: \(tones.count) tones")
            return
        case Property.presetCategories:
            categories = BandBoxProtocol.categories(r.value)
            record("← tone categories: \(categories.count)")
            return
        case Property.stemAI where !r.value.isEmpty:
            stemAI = r.value[0] == 1
        case Property.tuner where !r.value.isEmpty:
            let on = r.value[0] == 1
            if !on { tuner = nil }
            if !on, tunerKeepAlive != nil {
                // The speaker drops its tuner when a channel is selected or a jack goes in or out
                // (and on its own tuner button); one turned on here stays on until turned off here.
                send(BandBoxProtocol.set(Property.tuner, [1]))
            } else {
                tunerOn = on
            }
        case Property.tunerFeed:
            tuner = BandBoxProtocol.tunerReading(r.value)
            return  // ~10 per second; keep it out of the log
        case Property.tunerReference where r.value.count >= 2:
            tunerReference = Double(UInt16(r.value[0]) | UInt16(r.value[1]) << 8) / 10
        case Property.level where r.value.count >= 3:
            levels[UInt16(r.value[0]) << 8 | UInt16(r.value[1])] = Int(r.value[2])
        case Property.battery where !r.value.isEmpty:
            battery = Int(r.value[0] & 0x7F)
            externalPower = r.value[0] & 0x80 != 0
        case Property.modelName:
            deviceName = String(decoding: r.value, as: UTF8.self)
        case Property.keepAlive:
            return
        default:
            break
        }
        record("← \(String(format: "0x%04x", r.id)) = \(BandBoxProtocol.hex(r.value))")
    }

    /// Follows up the speaker's echo of a tone action (ch op NN target …), as the JBL app does.
    private func toneActionDone(channel: Int, _ action: ToneAction?, tone: Int, target: Int, name: String) {
        let playing = Self.guitarChannels.filter { presets[$0] == tone }
        switch action {
        case .save:
            // Save the edits we have as the saved tone, so the re-read replaces both.
            for c in playing { savedDetails[c] = toneDetails[c] }
            send(BandBoxProtocol.set(Property.toneDetailsQuery, [UInt8(tone)]))
        case .discard, .reset:
            for c in playing { toneDetails[c] = savedDetails[c] }
            send(BandBoxProtocol.set(Property.toneDetailsQuery, [UInt8(tone)]))
        case .saveAs:
            // The echo has ff for the tone and the new tone's ID as target.
            // A scratch tone isn't the player's: don't offer it for a tone button.
            if !ScratchFiller.isScratchName(name) { createdTone = CreatedTone(channel: channel, id: target) }
            send(BandBoxProtocol.get([Property.presetLibrary]))
            setPreset(target, channel: channel)
        case .rename:
            send(BandBoxProtocol.get([Property.presetLibrary]))
            send(BandBoxProtocol.set(Property.toneDetailsQuery, [UInt8(tone)]))
        case .delete:
            send(BandBoxProtocol.get([Property.presetLibrary]))
            for c in playing { setPreset(1, channel: c) }
        case nil:
            break
        }
    }

    private func requestInitialState() {
        send(BandBoxProtocol.get([Property.modelName, Property.battery, Property.stemAI,
                                  Property.tuner, Property.tunerReference, Property.streamVolume]))
        send(BandBoxProtocol.set(Property.levelQuery, [0, 0]))   // speaker answers with the volume event
        for (channel, k) in channelKeys {
            send(BandBoxProtocol.set(Property.levelQuery, [UInt8(channel), k]))
        }
        send(BandBoxProtocol.set(Self.channels.map { PropertyRecord(id: Property.channelQuery, value: [UInt8($0)]) }))
        send(BandBoxProtocol.set([1, 2].map { PropertyRecord(id: Property.stemTypeQuery, value: [UInt8($0)]) }))
        send(BandBoxProtocol.set(Self.stemChannels.map { PropertyRecord(id: Property.stemLevelQuery, value: [UInt8($0)]) }))
        send(BandBoxProtocol.get([Property.presetCategories]))
        send(BandBoxProtocol.get([Property.presetLibrary]))      // big reply, sent in fragments
        // The speaker answers with each guitar channel's preset and pickup events.
        send(BandBoxProtocol.set(Self.guitarChannels.map { PropertyRecord(id: Property.presetQuery, value: [UInt8($0)]) }))
        send(BandBoxProtocol.set(Self.guitarChannels.map { PropertyRecord(id: Property.pickupQuery, value: [UInt8($0)]) }))
    }

    // MARK: Discovery

    /// Stops searching (or drops the connection) until connect() is called.
    func disconnect() {
        guard link != .offline else { return }
        stopped = true
        rescanTimer?.invalidate()
        central.stopScan()
        candidates.removeAll()
        if let p = peripheral { central.cancelPeripheralConnection(p) }
        peripheral = nil
        link = .offline
        record("stopped connecting")
    }

    /// Starts searching again after disconnect().
    func connect() {
        stopped = false
        if central.state == .poweredOn { startSearching() } else { centralManagerDidUpdateState(central) }
    }

    private func startSearching() {
        link = .searching
        confirmed = false
        peripheral = nil
        writeCharacteristic = nil
        candidates.removeAll()
        rejected.removeAll()
        central.stopScan()
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        rescanTimer?.invalidate()
        // Restart the scan regularly: the speaker shows up under a new identifier after it rotates.
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            guard let self, self.link == .searching, self.peripheral == nil else { return }
            self.rejected.removeAll()
            self.central.stopScan()
            self.central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        }
        record("searching for the speaker…")
    }

    private func probeNext() {
        guard !stopped, peripheral == nil, !candidates.isEmpty else { return }
        let p = candidates.removeFirst()
        peripheral = p
        link = .connecting
        central.connect(p, options: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.peripheral === p, !self.confirmed else { return }
            self.reject(p)
        }
    }

    private func reject(_ p: CBPeripheral) {
        rejected.insert(p.identifier)
        central.cancelPeripheralConnection(p)
        peripheral = nil
        guard !stopped else { return }
        link = .searching
        probeNext()
    }

    func record(_ line: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        let stamped = "[\(f.string(from: Date()))] \(line)"
        print(stamped)
        log.append(stamped)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }
}

extension BandBoxClient: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: if stopped { link = .offline } else { startSearching() }
        case .unauthorized: link = .unauthorized
        default: link = .bluetoothOff
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData adv: [String: Any], rssi: NSNumber) {
        guard !stopped, !rejected.contains(p.identifier), !candidates.contains(where: { $0 === p }), peripheral !== p else { return }
        let name = p.name ?? (adv[CBAdvertisementDataLocalNameKey] as? String)
        let silent = adv[CBAdvertisementDataManufacturerDataKey] == nil
            && adv[CBAdvertisementDataServiceUUIDsKey] == nil
        if let name, name.localizedCaseInsensitiveContains("BandBox") {
            candidates.insert(p, at: 0)
        } else if name == nil, silent, rssi.intValue > -80 {
            candidates.append(p)
        } else {
            return
        }
        probeNext()
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self
        p.discoverServices([Self.commandService])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if p === peripheral { reject(p) }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p === peripheral || stopped else { return }
        if confirmed {
            record("disconnected: \(error?.localizedDescription ?? "no reason given")")
        }
        writeQueue.removeAll()
        writeInFlight = false
        fragments.removeAll()
        tunerOn = false
        tuner = nil
        tunerKeepAlive?.invalidate()
        tunerKeepAlive = nil
        toneDetails = [:]
        savedDetails = [:]
        if stopped { peripheral = nil } else { startSearching() }
    }
}

extension BandBoxClient: CBPeripheralDelegate {
    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == Self.commandService }) else {
            reject(p)
            return
        }
        confirmed = true
        deviceName = p.name
        p.discoverCharacteristics([Self.notifyChar, Self.writeChar], for: service)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for ch in service.characteristics ?? [] {
            if ch.uuid == Self.writeChar { writeCharacteristic = ch }
            if ch.uuid == Self.notifyChar { p.setNotifyValue(true, for: ch) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error {
            record("subscribe failed: \(error.localizedDescription)")
            return
        }
        link = .connected
        rescanTimer?.invalidate()
        central.stopScan()
        record("connected to \(p.name ?? "speaker")")
        requestInitialState()
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, let value = ch.value else { return }
        handle(value)
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        if let error { record("write failed: \(error.localizedDescription)") }
        writeInFlight = false
        pumpWrites()
    }
}
