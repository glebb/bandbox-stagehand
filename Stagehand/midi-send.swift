// Sends MIDI to Stagehand from a virtual source, for trying MIDI control without a controller.
// Usage: swift midi-send.swift pc 2  cc 81 127  press 82  note 60
//   pc N       Program Change N
//   cc N V     Control Change N = V
//   press N    a momentary switch on CC N: 127, then 0 after 0.15 s
//   note N     Note On N (velocity 100)
//   wait S     wait S seconds (to click Learn in Stagehand first)
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
    case let other: print("unknown:", other); exit(1)
    }
    Thread.sleep(forTimeInterval: 0.5)
}
