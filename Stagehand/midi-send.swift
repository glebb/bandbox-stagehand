// Sends MIDI to Stagehand from a virtual source, for trying MIDI control without a controller.
// Usage: swift midi-send.swift pc 2  cc 81 127  press 82  note 60
//   pc N       Program Change N
//   cc N V     Control Change N = V
//   press N    a momentary switch on CC N: 127, then 0 after 0.15 s
//   note N     Note On N (velocity 100)
//   wait S     wait S seconds (to click Learn in Stagehand first)
//   sysex F    a SysEx: manufacturer 0x7D, then file F's text (a Rocksmith song-tones message,
//              see ScratchTones.swift; Tests/song-tones.json is one)
// Messages go on MIDI channel 1, half a second apart, after a second for Stagehand to connect.
import CoreMIDI
import Foundation

var client = MIDIClientRef()
var source = MIDIEndpointRef()
MIDIClientCreateWithBlock("midi-send" as CFString, &client, nil)
MIDISourceCreateWithProtocol(client, "Stagehand test" as CFString, ._1_0, &source)

func send(_ status: UInt32, _ data1: Int, _ data2: Int = 0) {
    var list = MIDIEventList()
    let packet = MIDIEventListInit(&list, ._1_0)
    var word = 0x2000_0000 | status << 16 | UInt32(data1 & 0x7F) << 8 | UInt32(data2 & 0x7F)
    MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, &word)
    MIDIReceivedEventList(source, &list)
    print("sent", String(format: "%02X %d %d", status, data1, data2))
}

/// SysEx as UMP SysEx7 messages of up to 6 bytes: complete, or start, continue … end.
func sysex(_ data: [UInt8]) {
    let chunks = stride(from: 0, to: data.count, by: 6).map { Array(data[$0 ..< min($0 + 6, data.count)]) }
    for (i, chunk) in chunks.enumerated() {
        let status: UInt32 = chunks.count == 1 ? 0 : i == 0 ? 1 : i == chunks.count - 1 ? 3 : 2
        let b = (chunk + [0, 0, 0, 0, 0, 0]).map { UInt32($0 & 0x7F) }
        var words: [UInt32] = [0x3000_0000 | status << 20 | UInt32(chunk.count) << 16 | b[0] << 8 | b[1],
                               b[2] << 24 | b[3] << 16 | b[4] << 8 | b[5]]
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 2, &words)
        MIDIReceivedEventList(source, &list)
    }
    print("sent SysEx, \(data.count) bytes")
}

Thread.sleep(forTimeInterval: 1)
var args = Array(CommandLine.arguments.dropFirst())
func number() -> Int { args.isEmpty ? 0 : Int(args.removeFirst()) ?? 0 }
while !args.isEmpty {
    switch args.removeFirst() {
    case "pc": send(0xC0, number())
    case "cc": let n = number(); send(0xB0, n, number())
    case "press": let n = number(); send(0xB0, n, 127); Thread.sleep(forTimeInterval: 0.15); send(0xB0, n, 0)
    case "note": send(0x90, number(), 100)
    case "wait": Thread.sleep(forTimeInterval: Double(number()))
    case "sysex":
        guard let text = try? String(contentsOfFile: args.removeFirst(), encoding: .utf8) else { print("no such file"); exit(1) }
        sysex([0x7D] + Array(text.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
    case let other: print("unknown:", other); exit(1)
    }
    Thread.sleep(forTimeInterval: 0.5)
}
