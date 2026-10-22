// Answers what the Rocksmith scratch tones need from the speaker (rs-mac-companion rig-plan.md,
// step 3), in one run with a guitar in channel CH:
//   1. Can 0x3443 read any tone's details, or only the playing tone's?
//   2. Can a tone that isn't playing be edited (0x3445 op 01 / 02 / 04) and saved (0x3446 op 04)
//      without the channel switching to it? 0x3444 shows saved values, so a re-read after the
//      save tells whether the edits got in. If not, the same is tried with the tone selected.
//   3. How long one write takes: op 04 one at a time with response, then a burst without.
//   4. How many user tones fit: save as until the speaker refuses (CAP at most).
// It works on its own tones only, named "Probe…": made by save as from the playing tone, deleted
// at the end. The playing tone is never edited or saved; at the end the channel goes back to it.
// Build with build-scratch-probe.sh; run:
//   open -W --stdout "$PWD/captures/scratch-probe.log" ScratchProbe.app --args [CH] [CAP]
//   open -W --stdout "$PWD/captures/scratch-probe-cleanup.log" ScratchProbe.app --args cleanup
// CH: guitar channel 1 or 3 (default 3). CAP: most user tones to make in step 4 (default 64,
// 0 skips it). "cleanup" only deletes leftover "Probe" tones.
// Close the JBL app and Stagehand first: the speaker takes one control client.
import CoreBluetooth
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)

let args = Array(CommandLine.arguments.dropFirst())
let cleanupOnly = args.first == "cleanup"
let channel = cleanupOnly ? 3 : args.first.flatMap(Int.init) ?? 3
let fillCap = args.count > 1 ? Int(args[1]) ?? 64 : 64
let probePrefix = "Probe"

let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
func log(_ line: String) { print("[\(clock.string(from: Date()))] \(line)") }
func hex(_ b: [UInt8]) -> String { BandBoxProtocol.hex(b) }
func ms(_ t: TimeInterval) -> String { String(format: "%.0f ms", t * 1000) }

/// A record the speaker sent, with when it arrived.
struct Received {
    let at: Date
    let record: PropertyRecord
}

/// The Bluetooth side: finds the speaker as Stagehand does, and lets the probe below (on the main
/// thread) write and wait for records the speaker sends.
final class Link: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let service = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0000")
    static let notifyChar = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0001")
    static let writeChar = CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0002")

    private let queue = DispatchQueue(label: "ble")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var write: CBCharacteristic?
    private var candidates: [CBPeripheral] = []
    private var rejected = Set<UUID>()
    private var confirmed = false
    private var fragments: [UInt16: [UInt8]] = [:]

    private let lock = NSCondition()
    private var ready = false
    private var writesDone = 0
    private var writeError: Error?
    private(set) var received: [Received] = []   // guarded by lock

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: Used by the probe

    func waitUntilConnected(timeout: TimeInterval) -> Bool {
        wait(timeout) { self.ready }
    }

    /// How many records have arrived so far: pass it to `next` to look only at later ones.
    var mark: Int { lock.lock(); defer { lock.unlock() }; return received.count }

    /// Writes with response and waits for the write to be acknowledged; returns how long that took.
    @discardableResult
    func send(_ data: Data, _ label: String) -> TimeInterval? {
        log("→ \(label)  \(hex([UInt8](data)))")
        lock.lock()
        let before = writesDone
        writeError = nil
        lock.unlock()
        let start = Date()
        queue.async { self.peripheral?.writeValue(data, for: self.write!, type: .withResponse) }
        guard wait(5, { self.writesDone > before }) else { log("! write not acknowledged in 5 s"); return nil }
        if let writeError { log("! write failed: \(writeError.localizedDescription)"); return nil }
        return Date().timeIntervalSince(start)
    }

    /// Writes without response, as fast as CoreBluetooth takes them.
    func sendQuick(_ data: Data) {
        while queue.sync(execute: { peripheral?.canSendWriteWithoutResponse == false }) { Thread.sleep(forTimeInterval: 0.002) }
        queue.sync { peripheral?.writeValue(data, for: write!, type: .withoutResponse) }
    }

    /// The first record with `id` after `mark` that `match` accepts, waiting up to `timeout`.
    func next(_ id: UInt16, after mark: Int, timeout: TimeInterval = 3,
              where match: @escaping ([UInt8]) -> Bool = { _ in true }) -> Received? {
        var found: Received?
        _ = wait(timeout) {
            found = self.received.dropFirst(mark).first { $0.record.id == id && match($0.record.value) }
            return found != nil
        }
        return found
    }

    /// Every record with `id` after `mark`.
    func all(_ id: UInt16, after mark: Int) -> [Received] {
        lock.lock(); defer { lock.unlock() }
        return received.dropFirst(mark).filter { $0.record.id == id }
    }

    private func wait(_ timeout: TimeInterval, _ done: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        lock.lock(); defer { lock.unlock() }
        while !done() {
            if !lock.wait(until: end) { return done() }
        }
        return true
    }

    private func signal(_ change: () -> Void) {
        lock.lock(); change(); lock.broadcast(); lock.unlock()
    }

    // MARK: Finding the speaker

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            log("searching for the speaker")
            c.scanForPeripherals(withServices: nil, options: nil)
        case .unauthorized: log("! Bluetooth not allowed for ScratchProbe (System Settings > Privacy > Bluetooth)")
        default: log("! Bluetooth is off")
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData adv: [String: Any], rssi: NSNumber) {
        guard !confirmed, !rejected.contains(p.identifier), !candidates.contains(where: { $0 === p }), peripheral !== p else { return }
        let name = p.name ?? (adv[CBAdvertisementDataLocalNameKey] as? String)
        let silent = adv[CBAdvertisementDataManufacturerDataKey] == nil && adv[CBAdvertisementDataServiceUUIDsKey] == nil
        if let name, name.localizedCaseInsensitiveContains("BandBox") {
            candidates.insert(p, at: 0)
        } else if name == nil, silent, rssi.intValue > -80 {
            candidates.append(p)
        } else {
            return
        }
        probeNext()
    }

    private func probeNext() {
        guard !confirmed, peripheral == nil, !candidates.isEmpty else { return }
        let p = candidates.removeFirst()
        peripheral = p
        central.connect(p, options: nil)
        queue.asyncAfter(deadline: .now() + 6) {
            if self.peripheral === p, !self.confirmed { self.reject(p) }
        }
    }

    private func reject(_ p: CBPeripheral) {
        rejected.insert(p.identifier)
        central.cancelPeripheralConnection(p)
        peripheral = nil
        probeNext()
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self
        p.discoverServices([Self.service])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        if p === peripheral { reject(p) }
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        guard p === peripheral, confirmed else { return }
        log("! disconnected: \(error?.localizedDescription ?? "no reason given")")
        exit(1)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { reject(p); return }
        confirmed = true
        central.stopScan()
        p.discoverCharacteristics([Self.notifyChar, Self.writeChar], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        for ch in s.characteristics ?? [] {
            if ch.uuid == Self.writeChar { write = ch }
            if ch.uuid == Self.notifyChar { p.setNotifyValue(true, for: ch) }
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error: Error?) {
        if let error { log("! subscribe failed: \(error.localizedDescription)"); exit(1) }
        log("connected to \(p.name ?? "speaker")")
        signal { ready = true }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error: Error?) {
        signal { writesDone += 1; writeError = error }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error: Error?) {
        guard error == nil, let data = ch.value, let msg = BandBoxProtocol.parse(data) else { return }
        var payload = msg.payload
        if msg.fragmentTotal > 1 {
            if msg.fragmentIndex == 0 { fragments[msg.type] = nil }
            fragments[msg.type, default: []] += payload
            guard msg.fragmentIndex + 1 == msg.fragmentTotal else { return }
            payload = fragments.removeValue(forKey: msg.type) ?? payload
        }
        let (status, records) = BandBoxProtocol.records(payload)
        if status != 0 { log("← status \(String(format: "0x%04x", status)) (type \(msg.type))") }
        let now = Date()
        for r in records where r.id != Property.keepAlive && r.id != Property.tunerFeed {
            log("← \(String(format: "0x%04x", r.id)) \(hex(r.value))")
        }
        signal { received += records.map { Received(at: now, record: $0) } }
    }
}

// MARK: Speaker commands

let link = Link()

func library() -> [Tone] {
    let m = link.mark
    link.send(BandBoxProtocol.get([Property.presetLibrary]), "GET tone library")
    return link.next(Property.presetLibrary, after: m).map { BandBoxProtocol.tones($0.record.value) } ?? []
}

/// The tone playing on the channel.
func current() -> Int? {
    let m = link.mark
    link.send(BandBoxProtocol.set(Property.presetQuery, [UInt8(channel)]), "query channel \(channel)'s tone")
    return link.next(Property.preset, after: m, where: { $0.first == UInt8(channel) }).map { Int($0.record.value[1]) }
}

func details(_ id: Int) -> ToneDetails? {
    let m = link.mark
    link.send(BandBoxProtocol.set(Property.toneDetailsQuery, [UInt8(id)]), "query details of tone \(id)")
    return link.next(Property.toneDetails, after: m, where: { $0.first == UInt8(id) })
        .flatMap { BandBoxProtocol.toneDetails($0.record.value) }
}

func select(_ id: Int) {
    let m = link.mark
    link.send(BandBoxProtocol.set(Property.preset, [UInt8(channel), UInt8(id)]), "select tone \(id) on channel \(channel)")
    _ = link.next(Property.preset, after: m, timeout: 1.5, where: { $0 == [UInt8(channel), UInt8(id)] })
}

/// The tones this run made, deleted at the end.
var madeIDs: [Int] = []

/// Save as: a new user tone from `id` (with its unsaved edits); returns the new tone's ID.
func saveAs(_ id: Int, name: String) -> (id: Int, time: TimeInterval)? {
    let m = link.mark, start = Date()
    link.send(BandBoxProtocol.toneAction(.saveAs, channel: channel, tone: id, category: 7, name: name), "save tone \(id) as \(name)")
    guard let echo = link.next(Property.toneAction, after: m, where: { $0.count > 3 && $0[1] == ToneAction.saveAs.rawValue }),
          echo.record.value[3] != 0xFF else { return nil }
    madeIDs.append(Int(echo.record.value[3]))
    return (Int(echo.record.value[3]), echo.at.timeIntervalSince(start))
}

func save(_ id: Int) -> TimeInterval? {
    let m = link.mark, start = Date()
    link.send(BandBoxProtocol.toneAction(.save, channel: channel, tone: id), "save tone \(id)")
    return link.next(Property.toneAction, after: m, where: { $0.count > 2 && $0[1] == ToneAction.save.rawValue && $0[2] == UInt8(id) })
        .map { $0.at.timeIntervalSince(start) }
}

func delete(_ id: Int) {
    let m = link.mark
    link.send(BandBoxProtocol.toneAction(.delete, channel: channel, tone: id), "delete tone \(id)")
    _ = link.next(Property.toneAction, after: m, where: { $0.count > 2 && $0[1] == ToneAction.delete.rawValue })
}

func edit(_ id: Int, _ op: EffectOp, _ rest: [UInt8]) -> Data {
    BandBoxProtocol.set(Property.effectBlock, [UInt8(channel), UInt8(id), op.rawValue] + rest)
}

func setParam(_ id: Int, _ block: EffectBlock, _ param: UInt8, _ value: Float) -> Data {
    edit(id, .param, [UInt8(block.slot)] + BandBoxProtocol.le16(block.model) + [0xFF, 0x01, param] + BandBoxProtocol.f32(value))
}

func blockLine(_ b: EffectBlock?) -> String {
    guard let b, let slot = EffectSlot(rawValue: b.slot) else { return "none" }
    let model = slot.model(b.model)?.name ?? String(format: "0x%04x", b.model)
    let knobs = b.params.map { "\($0.id)=\($0.value)" }.joined(separator: " ")
    return "\(slot.name) \(model) \(b.bypassed ? "off" : "on") [\(knobs)]"
}

var findings: [String] = []
func finding(_ line: String) { log("== \(line)"); findings.append(line) }

/// Deletes the tones this run made, by ID (saving a tone that isn't playing renames it to the
/// playing tone's name), then any "Probe" tone the library shows. With many user tones the
/// library reply breaks off after about 1 KB, so it's read again until none is left.
func deleteProbeTones() {
    madeIDs.forEach(delete)
    madeIDs = []
    for _ in 0 ..< 5 {
        let left = library().filter { $0.isUser && $0.name.hasPrefix(probePrefix) }
        if left.isEmpty { return }
        left.forEach { delete($0.id) }
    }
}

// MARK: The probe

guard link.waitUntilConnected(timeout: 60) else { log("! speaker not found in 60 s (is the JBL app or Stagehand connected?)"); exit(1) }
Thread.sleep(forTimeInterval: 0.5)

if cleanupOnly {
    deleteProbeTones()
    log("left: " + library().filter(\.isUser).map { "\($0.id) \($0.name)" }.joined(separator: ", "))
    exit(0)
}

let tonesBefore = library()
guard let playing = current(), let playingTone = tonesBefore.first(where: { $0.id == playing }) else {
    log("! no tone on channel \(channel): is a guitar plugged in there? (pass 1 or 3)")
    exit(1)
}
finding("channel \(channel) plays \(playing) \(playingTone.name); \(tonesBefore.count) tones, user tones: "
        + tonesBefore.filter(\.isUser).map { "\($0.id) \($0.name)" }.joined(separator: ", "))
let leftovers = tonesBefore.filter { $0.isUser && $0.name.hasPrefix(probePrefix) }
if !leftovers.isEmpty { log("deleting leftovers of an earlier run"); leftovers.forEach { delete($0.id) } }

// 1. Reading a tone that isn't playing.
log("-- 1. details of tones that aren't playing")
let others = tonesBefore.filter { $0.id != playing && !leftovers.contains($0) }
for t in [others.first, others.first(where: \.isUser), others.last].compactMap({ $0 }).uniqued() {
    let m = link.mark
    let d = details(t.id)
    let switched = link.all(Property.preset, after: m).contains { $0.record.value.first == UInt8(channel) }
    finding("read tone \(t.id) \(t.name) while \(playing) plays: "
            + (d.map { "\($0.blocks.count) blocks" } ?? "no answer") + (switched ? ", and the channel switched" : ""))
}

// The probe's own tone, a copy of the playing tone.
log("-- making the probe tone")
guard let made = saveAs(playing, name: "\(probePrefix) A") else { log("! save as got no new ID"); exit(1) }
let probe = made.id
let afterSaveAs = current()
finding("save as made tone \(probe) in \(ms(made.time)); channel \(channel) now plays \(afterSaveAs.map(String.init) ?? "?")")
if afterSaveAs != playing { select(playing) }
guard let original = details(probe), let delay = original.block(.delay), let fx = original.block(.fx),
      let reverb = original.block(.reverb) else { log("! no details for the probe tone"); deleteProbeTones(); exit(1) }
log("probe tone: \(blockLine(fx)); \(blockLine(delay)); \(blockLine(reverb))")

// 2. Editing and saving it while another tone plays.
/// Sends a set of edits to the probe tone, saves it, reads it back; true if every edit got in.
func editAndSave(_ label: String) -> Bool {
    let time: Float = delay.value(1) == 777 ? 555 : 777
    let fxModel: UInt16 = fx.model == 0x0B ? 0x0F : 0x0B    // Chorus, or Green Phaser if it is one
    let m = link.mark
    log("say: strum now; the sound should not change (\(label))")
    speak("Strum now. The sound should not change.")
    link.send(setParam(probe, delay, 1, time), "op 04: delay Time \(time)")
    link.send(setParam(probe, delay, 0, 33), "op 04: delay Mix 33")
    link.send(edit(probe, .model, [UInt8(EffectSlot.fx.rawValue)] + BandBoxProtocol.le16(fxModel) + [0xFF, 0x00]),
              "op 02: FX model \(EffectSlot.fx.model(fxModel)!.name)")
    var flipped = reverb
    flipped.bypassed.toggle()
    link.send(edit(probe, .bypass, flipped.bytes), "op 01: reverb \(flipped.bypassed ? "off" : "on")")
    Thread.sleep(forTimeInterval: 0.5)
    let saved = save(probe)
    let switched = link.all(Property.preset, after: m).filter { $0.record.value.first == UInt8(channel) }
    guard let after = details(probe) else { finding("\(label): no details after the save"); return false }
    let timeIn = after.block(.delay)?.value(1) == time, mixIn = after.block(.delay)?.value(0) == 33
    let modelIn = after.block(.fx)?.model == fxModel, bypassIn = after.block(.reverb)?.bypassed == flipped.bypassed
    finding("\(label): save " + (saved.map { "echoed in \(ms($0))" } ?? "not echoed")
            + "; op 04 time \(timeIn ? "saved" : "lost"), mix \(mixIn ? "saved" : "lost"), op 02 model \(modelIn ? "saved" : "lost")"
            + ", op 01 bypass \(bypassIn ? "saved" : "lost")"
            + (switched.isEmpty ? "; channel didn't switch" : "; channel switched to " + switched.map { "\($0.record.value[1])" }.joined(separator: ", ")))
    log("now: \(blockLine(after.block(.fx))); \(blockLine(after.block(.delay))); \(blockLine(after.block(.reverb)))")
    return timeIn && mixIn && modelIn && bypassIn
}

func speak(_ text: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/say")
    p.arguments = [text]
    try? p.run()
}

log("-- 2. edit and save the probe tone while \(playing) plays")
if !editAndSave("silent edit (tone \(probe) not playing)") {
    log("-- 2b. the same with the probe tone selected")
    select(probe)
    _ = editAndSave("selected edit (tone \(probe) playing)")
    select(playing)
}
speak("Stop strumming.")

// 3. Write speed, on the probe tone.
log("-- 3. write speed")
var times: [TimeInterval] = []
var echoes: [TimeInterval] = []
for i in 0 ..< 20 {
    let value = Float(200 + i * 10)
    let m = link.mark, start = Date()
    if let t = link.send(setParam(probe, delay, 1, value), "op 04 delay Time \(value)") { times.append(t) }
    if let e = link.next(Property.effectBlock, after: m, timeout: 1) { echoes.append(e.at.timeIntervalSince(start)) }
}
func stats(_ v: [TimeInterval]) -> String {
    guard !v.isEmpty else { return "none" }
    let s = v.sorted()
    return "median \(ms(s[s.count / 2])), max \(ms(s.last!)) (\(v.count))"
}
finding("op 04 with response, one at a time: write acknowledged \(stats(times)); echo \(stats(echoes))")

let burst = 20, m3 = link.mark, start3 = Date()
for i in 0 ..< burst { link.sendQuick(setParam(probe, delay, 1, Float(500 + i))) }
let sentIn = Date().timeIntervalSince(start3)
Thread.sleep(forTimeInterval: 2)
let burstEchoes = link.all(Property.effectBlock, after: m3)
let last = burstEchoes.last.map { $0.at.timeIntervalSince(start3) }
_ = save(probe)
let burstSaved = details(probe)?.block(.delay)?.value(1)
finding("op 04 burst without response: \(burst) sent in \(ms(sentIn)), \(burstEchoes.count) echoed"
        + (last.map { ", last echo after \(ms($0))" } ?? "") + "; saved Time \(burstSaved.map { "\($0)" } ?? "?") (last sent \(500 + burst - 1))")

let m3s = link.mark, start3s = Date()
select(probe)
let selectTime = link.next(Property.preset, after: m3s, where: { $0 == [UInt8(channel), UInt8(probe)] }).map { $0.at.timeIntervalSince(start3s) }
select(playing)
let readStart = Date()
_ = details(probe)
finding("select echoed in \(selectTime.map(ms) ?? "?"); details read in \(ms(Date().timeIntervalSince(readStart)))")

// 4. How many user tones fit.
if fillCap > 0 {
    log("-- 4. user tones until the speaker refuses (at most \(fillCap))")
    var made: [TimeInterval] = []
    var refused = false
    for i in 1 ... fillCap {
        guard let t = saveAs(probe, name: "\(probePrefix) \(i)") else { refused = true; break }
        made.append(t.time)
        if current() != playing { select(playing) }
    }
    let users = library().filter(\.isUser).count
    finding(refused ? "user tones: the speaker refused save as number \(made.count + 1); \(users) user tones then"
                    : "user tones: \(made.count) more made without a refusal (\(users) user tones)")
    finding("save as \(stats(made))")
}

// Clean up: every Probe tone goes, and the channel plays what it played before.
log("-- cleaning up")
deleteProbeTones()
select(playing)
let end = library()
finding("done: channel \(channel) plays \(current().map(String.init) ?? "?"); user tones now: "
        + end.filter(\.isUser).map { "\($0.id) \($0.name)" }.joined(separator: ", "))

print("\nFindings:")
findings.forEach { print("  \($0)") }
exit(0)

extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}
