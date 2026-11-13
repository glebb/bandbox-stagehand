// A bench link to the speaker for measurements (tone-bench/): connects as Stagehand does and
// serves the control channel on 127.0.0.1:PORT, one line per command, so a script can drive the
// speaker while it records what comes out:
//   set ID HEX            SET property ID (hex) to the bytes HEX, written with response → "ok" / "err"
//   get ID[,ID…]          GET → "ok"; the answer arrives as records
//   mark                  → how many records have arrived so far
//   wait ID MARK MS [HEX] → the first record ID after MARK whose value starts with HEX, as
//                           "INDEX ID HEX", or "none" after MS milliseconds
//   recv MARK             → every record after MARK, one "INDEX ID HEX" a line, then "."
//   quit                  the bench exits
// Build with build-tone-bench.sh; run: open ToneBench.app --args [PORT]   (default 47800)
// Close the JBL app and Stagehand first: the speaker takes one control client.
import CoreBluetooth
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
let port = CommandLine.arguments.dropFirst().first.flatMap(UInt16.init) ?? 47800

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }
func bytes(_ s: Substring) -> [UInt8]? {
    var out: [UInt8] = [], rest = s
    while rest.count >= 2 {
        guard let b = UInt8(rest.prefix(2), radix: 16) else { return nil }
        out.append(b); rest = rest.dropFirst(2)
    }
    return rest.isEmpty ? out : nil
}

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
    private(set) var ready = false
    private(set) var state = "starting"
    private var writesDone = 0
    private var writeError: Error?
    private var received: [PropertyRecord] = []   // guarded by lock

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    var mark: Int { lock.lock(); defer { lock.unlock() }; return received.count }

    func send(_ data: Data) -> Bool {
        guard ready else { return false }
        lock.lock()
        let before = writesDone
        writeError = nil
        lock.unlock()
        queue.async { self.peripheral?.writeValue(data, for: self.write!, type: .withResponse) }
        return wait(5) { self.writesDone > before } && writeError == nil
    }

    func next(_ id: UInt16, after mark: Int, timeout: TimeInterval, prefix: [UInt8]) -> (Int, PropertyRecord)? {
        var found: (Int, PropertyRecord)?
        _ = wait(timeout) {
            if let i = self.received.indices.dropFirst(mark).first(where: {
                self.received[$0].id == id && self.received[$0].value.starts(with: prefix)
            }) { found = (i, self.received[i]) }
            return found != nil
        }
        return found
    }

    func all(after mark: Int) -> [(Int, PropertyRecord)] {
        lock.lock(); defer { lock.unlock() }
        return received.indices.dropFirst(mark).map { ($0, received[$0]) }
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

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            state = "searching"
            c.scanForPeripherals(withServices: nil, options: nil)
        case .unauthorized: state = "Bluetooth not allowed"
        default: state = "Bluetooth off (\(c.state.rawValue))"
        }
        print(state)
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
        print("disconnected: \(error?.localizedDescription ?? "no reason given")")
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
        if let error { print("subscribe failed: \(error.localizedDescription)"); exit(1) }
        state = "connected to \(p.name ?? "speaker")"
        print(state)
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
        let records = BandBoxProtocol.records(payload).records.filter { $0.id != Property.keepAlive }
        signal { received += records }
    }
}

let link = Link()

func answer(_ line: String) -> String {
    let parts = line.split(separator: " ")
    func id(_ s: Substring) -> UInt16? { UInt16(s, radix: 16) }
    func show(_ r: (Int, PropertyRecord)) -> String { "\(r.0) \(String(format: "%04x", r.1.id)) \(hex(r.1.value))" }
    switch parts.first {
    case "state": return link.state
    case "set":
        guard parts.count == 3, let i = id(parts[1]), let v = bytes(parts[2]) else { return "err usage" }
        return link.send(BandBoxProtocol.set(i, v)) ? "ok" : "err"
    case "get":
        guard parts.count == 2 else { return "err usage" }
        let ids = parts[1].split(separator: ",").compactMap(id)
        return link.send(BandBoxProtocol.get(ids)) ? "ok" : "err"
    case "mark": return String(link.mark)
    case "wait":
        guard parts.count >= 4, let i = id(parts[1]), let m = Int(parts[2]), let ms = Double(parts[3]),
              let prefix = parts.count > 4 ? bytes(parts[4]) : [] else { return "err usage" }
        return link.next(i, after: m, timeout: ms / 1000, prefix: prefix).map(show) ?? "none"
    case "recv":
        guard parts.count == 2, let m = Int(parts[1]) else { return "err usage" }
        return (link.all(after: m).map(show) + ["."]).joined(separator: "\n")
    case "quit": exit(0)
    default: return "err unknown"
    }
}

// One client at a time, on a plain socket.
let server = socket(AF_INET, SOCK_STREAM, 0)
var yes: Int32 = 1
setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
var addr = sockaddr_in()
addr.sin_family = sa_family_t(AF_INET)
addr.sin_port = port.bigEndian
addr.sin_addr.s_addr = inet_addr("127.0.0.1")
let bound = withUnsafePointer(to: &addr) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
}
guard bound == 0, listen(server, 4) == 0 else { print("can't listen on \(port)"); exit(1) }
print("listening on 127.0.0.1:\(port)")
signal(SIGPIPE, SIG_IGN)
while true {
    let client = accept(server, nil, nil)
    guard client >= 0 else { continue }
    var pending = [UInt8]()
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(client, &buffer, buffer.count)
        guard n > 0 else { break }
        pending += buffer[..<n]
        while let nl = pending.firstIndex(of: 0x0A) {
            let line = String(decoding: pending[..<nl], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            pending.removeSubrange(...nl)
            let reply = Array((answer(line) + "\n").utf8)
            _ = reply.withUnsafeBufferPointer { Darwin.write(client, $0.baseAddress, $0.count) }
        }
    }
    close(client)
}
