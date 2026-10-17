// BLE scanner / GATT dumper for macOS. Build: swiftc ble-scan.swift -o ble-scan
// Usage:
//   ./ble-scan                 # scan ~15s, list all BLE advertisers
//   ./ble-scan "Bandox"        # scan, then connect to first device whose name
//                              # contains "Bandox" and dump its full GATT tree
//   ./ble-scan "Band" listen 180  # connect, subscribe to the vendor (excelpoint)
//                              # notify characteristics and log everything for 180s
import Foundation
import CoreBluetooth

let nameFilter = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil
let scanSeconds = 15.0
let listenMode = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "listen"
let listenSeconds = CommandLine.arguments.count > 3 ? Double(CommandLine.arguments[3]) ?? 120 : 120
let vendorPrefix = "65786365" // ASCII "exce" — the excelpoint.* services

// Timed writes to com/0002, given after the "com" arg as "<seconds>:<hex>", e.g.
//   BLEScan auto listen 15 com 2:00dd020001000500003101000001 8:00dd02...
// Seconds are relative to the moment the com notify subscription succeeds.
let sendSteps: [(Double, Data)] = CommandLine.arguments.dropFirst(5).compactMap { arg in
    let parts = arg.split(separator: ":", maxSplits: 1)
    guard parts.count == 2, let t = Double(parts[0]) else { return nil }
    var bytes = Data()
    var hex = Substring(parts[1].replacingOccurrences(of: " ", with: ""))
    while hex.count >= 2 {
        guard let b = UInt8(hex.prefix(2), radix: 16) else { return nil }
        bytes.append(b); hex = hex.dropFirst(2)
    }
    return (t, bytes)
}

setvbuf(stdout, nil, _IOLBF, 0) // stdout goes to a file; flush every line

let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"; return f }()
func stamp() -> String { clock.string(from: Date()) }

func describe(_ d: Data) -> String {
    let hex = d.map { String(format: "%02x", $0) }.joined(separator: " ")
    let ascii = String(d.map { (0x20...0x7e).contains($0) ? Character(UnicodeScalar($0)) : "." })
    return "(\(d.count)B) \(hex)  |\(ascii)|"
}

func shortName(_ ch: CBCharacteristic) -> String {
    let u = ch.uuid.uuidString
    if u.hasPrefix(vendorPrefix) { return (u.contains("636F6D") ? "com" : "cnl") + "/" + u.suffix(4) }
    return u
}

final class Scanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    var central: CBCentralManager!
    var target: CBPeripheral?
    var seen = Set<UUID>()
    var pendingChars = 0
    var listenTimerStarted = false
    // "auto" filter: the speaker rotates its address and advertises nothing, so probe
    // nearby silent devices and keep the first one that has the excelpoint com service.
    var candidates: [CBPeripheral] = []
    var rejected = Set<UUID>()
    var confirmed = false
    var writeChar: CBCharacteristic?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn:
            FileHandle.standardError.write("Bluetooth on — scanning \(Int(scanSeconds))s…\n".data(using: .utf8)!)
            c.scanForPeripherals(withServices: nil, options:
                [CBCentralManagerScanOptionAllowDuplicatesKey: false])
            DispatchQueue.main.asyncAfter(deadline: .now() + scanSeconds) {
                if self.target == nil && !self.confirmed {
                    if nameFilter != nil { print("\n(no device matched \"\(nameFilter!)\")") }
                    exit(0)
                }
            }
        case .unauthorized:
            print("ERROR: Bluetooth permission denied for this process (TCC). " +
                  "Grant it in System Settings > Privacy & Security > Bluetooth, " +
                  "or use the LightBlue app instead.")
            exit(1)
        case .poweredOff:
            print("ERROR: Bluetooth is off."); exit(1)
        default:
            print("Bluetooth state: \(c.state.rawValue)")
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral,
                        advertisementData adv: [String: Any], rssi: NSNumber) {
        if !seen.insert(p.identifier).inserted { return }
        let name = p.name ?? (adv[CBAdvertisementDataLocalNameKey] as? String) ?? "—"
        var line = "• \(name)  [\(p.identifier)]  rssi=\(rssi)"
        if let svcs = adv[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            line += "  svcs=\(svcs.map{$0.uuidString})"
        }
        if let mfg = adv[CBAdvertisementDataManufacturerDataKey] as? Data {
            line += "  mfg=\(mfg.map{String(format:"%02x",$0)}.joined())"
        }
        print(line)

        if nameFilter == "auto" {
            let silent = adv[CBAdvertisementDataManufacturerDataKey] == nil
                && adv[CBAdvertisementDataServiceUUIDsKey] == nil
            if name.localizedCaseInsensitiveContains("BandBox") {
                candidates.insert(p, at: 0)
            } else if name == "—" && silent && rssi.intValue > -75 {
                candidates.append(p)
            }
            if target == nil { probeNext() }
            return
        }

        if let f = nameFilter, target == nil,
           name.localizedCaseInsensitiveContains(f) || p.identifier.uuidString.hasPrefix(f.uppercased()) {
            target = p
            c.stopScan()
            print("\n>>> connecting to \(name) …")
            c.connect(p, options: nil)
        }
    }

    func probeNext() {
        guard target == nil, !candidates.isEmpty else { return }
        let p = candidates.removeFirst()
        target = p
        print("\n>>> probing \(p.identifier) …")
        central.connect(p, options: nil)
    }

    func reject(_ p: CBPeripheral, _ why: String) {
        print("[\(stamp())] not the speaker (\(why))")
        rejected.insert(p.identifier)
        target = nil
        central.cancelPeripheralConnection(p)
        probeNext()
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        p.delegate = self
        if listenMode {
            print("[\(stamp())] connected to \(p.name ?? "?")")
            // 5th arg "com" = only the com channel (subscribing to cnl may get us kicked)
            let comOnly = CommandLine.arguments.count > 4 && CommandLine.arguments[4] == "com"
            var svcs = [CBUUID(string: "65786365-6C70-6F69-6E74-2E636F6D0000")]
            if !comOnly { svcs.append(CBUUID(string: "65786365-6C70-6F69-6E74-2E636E6C0000")) }
            p.discoverServices(svcs)
        } else {
            p.discoverServices(nil)
        }
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error e: Error?) {
        if nameFilter == "auto" && !confirmed { reject(p, "connect failed"); return }
        print("[\(stamp())] connect failed: \(e?.localizedDescription ?? "?") — retrying")
        c.connect(p, options: nil)
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error e: Error?) {
        if rejected.contains(p.identifier) { return }
        if nameFilter == "auto" && !confirmed { reject(p, "disconnected while probing"); return }
        print("[\(stamp())] DISCONNECTED: \(e?.localizedDescription ?? "no error") — reconnecting")
        if listenMode { c.connect(p, options: nil) } else { exit(1) }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices e: Error?) {
        guard let svcs = p.services else { return }
        if nameFilter == "auto" && !confirmed {
            if svcs.isEmpty { reject(p, "no excelpoint service"); return }
            confirmed = true
            print("[\(stamp())] found \(p.name ?? "speaker") [\(p.identifier)]")
        }
        pendingChars = svcs.count
        for s in svcs {
            print("SERVICE \(s.uuid)")
            p.discoverCharacteristics(nil, for: s)
        }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error e: Error?) {
        if listenMode {
            for ch in (s.characteristics ?? []) {
                if ch.uuid.uuidString.hasPrefix(vendorPrefix) && ch.uuid.uuidString.contains("636F6D")
                    && ch.properties.contains(.write) { writeChar = ch }
                if ch.properties.contains(.notify) || ch.properties.contains(.indicate) {
                    p.setNotifyValue(true, for: ch)
                }
            }
            return
        }
        for ch in (s.characteristics ?? []) {
            var props: [String] = []
            let P = ch.properties
            if P.contains(.read) { props.append("read") }
            if P.contains(.write) { props.append("write") }
            if P.contains(.writeWithoutResponse) { props.append("writeNoResp") }
            if P.contains(.notify) { props.append("notify") }
            if P.contains(.indicate) { props.append("indicate") }
            print("    CHAR \(ch.uuid)  [\(props.joined(separator: ","))]")
        }
        pendingChars -= 1
        if pendingChars <= 0 {
            print("\n(GATT dump complete)")
            exit(0)
        }
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor ch: CBCharacteristic, error e: Error?) {
        if let e { print("[\(stamp())] subscribe \(shortName(ch)) FAILED: \(e.localizedDescription)") }
        else {
            print("[\(stamp())] subscribed \(shortName(ch)) (notifying=\(ch.isNotifying))")
            if !listenTimerStarted {
                listenTimerStarted = true
                for (t, bytes) in sendSteps {
                    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
                        guard let w = self.writeChar else { print("[\(stamp())] no write characteristic!"); return }
                        print("[\(stamp())] \(shortName(w)) -> \(describe(bytes))")
                        p.writeValue(bytes, for: w, type: .withResponse)
                    }
                }
                central.stopScan()
                print("[\(stamp())] listening for \(Int(listenSeconds))s — use the speaker and the app now")
                DispatchQueue.main.asyncAfter(deadline: .now() + listenSeconds) {
                    print("[\(stamp())] done listening"); exit(0)
                }
            }
        }
    }

    func peripheral(_ p: CBPeripheral, didWriteValueFor ch: CBCharacteristic, error e: Error?) {
        if let e { print("[\(stamp())] write \(shortName(ch)) FAILED: \(e.localizedDescription)") }
        else { print("[\(stamp())] write \(shortName(ch)) acknowledged") }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor ch: CBCharacteristic, error e: Error?) {
        if let e { print("[\(stamp())] \(shortName(ch)) error: \(e.localizedDescription)"); return }
        print("[\(stamp())] \(shortName(ch)) <- \(describe(ch.value ?? Data()))")
    }
}

let s = Scanner()
RunLoop.main.run()
