// Prints what Match amps makes of a song tones message on given templates, for tone-bench/verify.py:
//   match-cli < {"message": {...song tones, version 2...}, "templates": [{"name": …, "blocks": [{"slot": 3, "model": 774, "on": true, "params": {"0": 55}}]}]}
// one template per tone, by index. Out: per tone, the template's blocks and the matched ones.
import Foundation

let input = try! JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String: Any]
let text = String(data: try! JSONSerialization.data(withJSONObject: input["message"]!), encoding: .utf8)!
let request = SongTonesRequest.parse([SongTonesRequest.manufacturer] + Array(text.utf8))!
let templates = (input["templates"] as! [[String: Any]]).map { t in
    ToneDetails(id: 0, name: t["name"] as? String ?? "", blocks: (t["blocks"] as! [[String: Any]]).map { b in
        EffectBlock(slot: b["slot"] as! Int, model: UInt16(b["model"] as! Int), bypassed: !(b["on"] as! Bool),
                    params: (b["params"] as! [String: NSNumber]).map { EffectParam(id: UInt8($0.key)!, value: $0.value.floatValue) }.sorted { $0.id < $1.id })
    })
}
func out(_ blocks: [KnownBlock]) -> [[String: Any]] {
    blocks.map { ["slot": $0.slot, "model": Int($0.model), "on": !$0.bypassed,
                  "params": Dictionary(uniqueKeysWithValues: $0.params.map { (String($0.key), Double($0.value)) })] }
}
var result: [[String: Any]] = []
for (tone, template) in zip(request.tones, templates) {
    var warnings: [String] = [], notes: [String] = []
    let matched = ScratchPlan.target(template: template, tone: tone, matchAmp: true, warnings: &warnings, notes: &notes)
    func level(_ blocks: [KnownBlock]) -> Any {
        func b(_ slot: EffectSlot) -> KnownBlock? { blocks.first { $0.slot == slot.rawValue } }
        return b(.amp).flatMap { GearMatch.level(amp: $0, cab: b(.cab), input: GearMatch.input(compressor: b(.compressor), distortion: b(.distortion))) } ?? NSNull()
    }
    result.append(["key": tone.key, "template": template.name, "note": notes.first ?? "", "was": out(template.blocks.map(KnownBlock.init)),
                   "matched": out(matched), "level_was": level(template.blocks.map(KnownBlock.init)), "level_matched": level(matched)])
}
print(String(data: try! JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), encoding: .utf8)!)
