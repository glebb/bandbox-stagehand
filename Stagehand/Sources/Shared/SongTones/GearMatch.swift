import Foundation

// Match amps: a song tone's rig, as the game has it, on the BandBox's own gear, at the template's level.
//
// The way rs-tonehost does it for Helix Native (rearmed-mods, tonehost/helix): the game's amp picks a
// model, its gain and drive pedals say how hard that model is driven, its tone knobs carry over, and the
// level is set by measurement so every tone comes out as loud as it should. The BandBox can't be measured
// while a song loads, so it was measured once (tone-bench, BandBoxCalibration.swift): what each amp puts
// out over its Drive and its input, and what the Volume knob, the cabs and the pedals add. From that:
//
//   - the amp is the one of the rig's family that can be driven as hard as the tone's "drive" asks;
//   - its Drive is where that amp is as saturated as the drive asks, with the rig's drive pedal (a
//     Precision Drive, by the pedal's gain) in front of it if the rig has one;
//   - Bass, Mid and Treble are the game's, and the cab the nearest to the rig's;
//   - its Volume is what makes the tone as loud as its template was, by the same tables.
//
// The gate, the compressor and a wah stay the template's. A tone without a guitar amp in its rig (a bass,
// an acoustic through a DI) or on a template without one stays as it is.
enum GearMatch {
    struct Match: Equatable {
        var blocks: [Int: KnownBlock]   // the template's blocks this changes, by slot
        var note: String                // what was picked, for the log
    }

    // MARK: The tables, read

    /// `points` (by rising x) at `x`, straight lines between them; past the ends, the end segment goes on.
    static func value(_ points: [(Double, Double)], at x: Double) -> Double {
        guard points.count > 1 else { return points.first?.1 ?? 0 }
        let i = min(max(points.firstIndex { $0.0 >= x } ?? points.count - 1, 1), points.count - 1)
        let (a, b) = (points[i - 1], points[i])
        return a.1 + (b.1 - a.1) * (x - a.0) / (b.0 - a.0)
    }

    /// The x where `points` (rising in both) reach `y`.
    static func inverse(_ points: [(Double, Double)], of y: Double) -> Double {
        value(points.map { ($0.1, $0.0) }, at: y)
    }

    private static func clamped(_ xs: [Double], _ x: Double) -> (Int, Double) {
        let x = min(max(x, xs[0]), xs[xs.count - 1])
        let i = min(max(xs.firstIndex { $0 >= x } ?? xs.count - 1, 1), xs.count - 1)
        return (i, (x - xs[i - 1]) / (xs[i] - xs[i - 1]))
    }

    /// What amp `model` puts out, in dB, at `drive` with `input` dB at its input (Volume 50, its own tone
    /// knobs, the UK 1960 cab); nil for an amp that wasn't measured.
    static func output(_ model: UInt16, drive: Double, input: Double) -> Double? {
        guard let rows = BandBoxCalibration.amps[model] else { return nil }
        let (d, df) = clamped(BandBoxCalibration.drives, drive), (u, uf) = clamped(BandBoxCalibration.inputs, input)
        func row(_ r: [Double]) -> Double { r[u - 1] + (r[u] - r[u - 1]) * uf }
        return row(rows[d - 1]) + (row(rows[d]) - row(rows[d - 1])) * df
    }

    /// How saturated the amp is there, 0-1: 0 while its output follows its input dB for dB, 1 when it
    /// doesn't follow at all. Read over 8 dB around `input`.
    static func saturation(_ model: UInt16, drive: Double, input: Double) -> Double? {
        let inputs = BandBoxCalibration.inputs
        let low = max(input - 4, inputs[0]), high = min(input + 4, inputs[inputs.count - 1])
        guard high > low, let a = output(model, drive: drive, input: low), let b = output(model, drive: drive, input: high) else { return nil }
        return min(max(1 - (b - a) / (high - low), 0), 1)
    }

    /// How saturated a tone should be for the message's drive (0-1: clean below 1/3, crunch to 2/3, heavy above).
    static func target(drive: Double) -> Double {
        value([(0, 0.05), (1.0 / 3, 0.3), (2.0 / 3, 0.72), (1, 0.97)], at: min(max(drive, 0), 1))
    }

    /// What reaches the amp, in dB around the bench's test signal: a guitar, raised by the compressor's
    /// Output and the Precision Drive if they are on. (What the compressor takes off a loud note isn't in it.)
    static func input(compressor: KnownBlock?, distortion: KnownBlock?) -> Double {
        var u = BandBoxCalibration.guitar
        if let c = compressor, !c.bypassed { u += Double(c.params[4] ?? 0) * BandBoxCalibration.compressorOutput }
        if let d = distortion, !d.bypassed, d.model == precisionDrive {
            u += value(BandBoxCalibration.pedalDrive.map { ($0.knob, $0.dB) }, at: Double(d.params[0] ?? 44))
            u += value(BandBoxCalibration.pedalLevel.map { ($0.knob, $0.dB) }, at: Double(d.params[2] ?? 100))
            u -= (100 - Double(d.params[1] ?? 51)) * BandBoxCalibration.pedalBright
        }
        return u
    }

    /// A tone's level in dB by the tables: its amp at its Drive and input, the Volume, the tone knobs and
    /// the cab. nil for an amp that wasn't measured or is off.
    static func level(amp: KnownBlock, cab: KnownBlock?, input: Double) -> Double? {
        guard !amp.bypassed, let knobs = ampDefaults[amp.model] else { return nil }
        func knob(_ id: UInt8) -> Double { Double(amp.params[id] ?? Float(knobs[Int(id)])) }
        guard let out = output(amp.model, drive: knob(0), input: input) else { return nil }
        let eq = (knob(2) - knobs[2]) * BandBoxCalibration.mid + (knob(3) - knobs[3]) * BandBoxCalibration.treble
        let box = cab.map { $0.bypassed ? BandBoxCalibration.cabOff : BandBoxCalibration.cabs[$0.model] ?? 0 } ?? 0
        return out + value(BandBoxCalibration.volume.map { ($0.knob, $0.dB) }, at: knob(4)) + eq + box
    }

    // MARK: The game's gear

    static let precisionDrive: UInt16 = 0x04

    /// The guitar amps' own knobs (Drive, Bass, Mid, Treble, Volume), which the tables were measured at.
    static let ampDefaults: [UInt16: [Double]] = [
        0x0006: [32, 55, 27, 79, 59], 0x0106: [54, 73, 40, 63, 66], 0x0206: [53, 60, 49, 48, 70], 0x0306: [65, 64, 45, 65, 62],
        0x0406: [100, 94, 40, 60, 55], 0x0506: [66, 43, 50, 77, 43], 0x0606: [0, 67, 36, 57, 68], 0x0706: [100, 67, 36, 57, 62],
    ]

    /// A game amp's family, and the BandBox amps that can stand in for it, the cleanest first.
    enum Family: CaseIterable {
        case american, jazz, chime, british, boogie, highGain

        init?(gear: String) {
            func any(_ prefixes: String...) -> Bool { prefixes.contains(where: gear.hasPrefix) }
            if any("Amp_CA100", "Amp_HG180") { self = .highGain }
            else if any("Amp_CA85", "Amp_HG100") { self = .boogie }
            else if any("Amp_Marshall", "Amp_GB", "Amp_HG500", "Amp_EN50", "Amp_Orange") { self = .british }
            else if any("Amp_EN30", "Amp_BT") { self = .chime }
            else if any("Amp_CS") { self = .jazz }
            else if any("Amp_TW", "Amp_AT", "Amp_CA38", "Amp_Gibson", "Amp_Epiphone") { self = .american }
            else { return nil }
        }

        var amps: [UInt16] {
            switch self {
            case .american: [0x0006, 0x0206, 0x0506]      // American Clean, Yellow Tweed, Vintage Drive
            case .jazz: [0x0106, 0x0206]                  // Jazz Sound, Yellow Tweed
            case .chime: [0x0006, 0x0506, 0x0306]         // American Clean, Vintage Drive, UK Crunch
            case .british: [0x0306, 0x0406]               // UK Crunch, British Lead
            case .boogie: [0x0006, 0x0606]                // American Clean, American Gain Stack
            case .highGain: [0x0006, 0x0706]              // American Clean, US Metal
            }
        }
    }

    /// The BandBox cab nearest a game cab ("Cab_Marshall1960a_57_Cone"), or nil to keep the template's:
    /// a bass cab, a PA, or one that isn't known.
    static func cab(gear: String) -> UInt16? {
        let name = gear.hasPrefix("Cab_") ? String(gear.dropFirst(4)) : gear
        let table: [(String, String)] = [
            ("Marshall1936", "UK 2550 2x12"), ("Marshall", "UK 1960 4x12"), ("GB412", "UK 1960 4x12"),
            ("CA412", "Mebo 4x12"), ("CA215", "Mebo 4x12"), ("CA112", "TR65 2x12"),
            ("EN", "Voks 2x12"), ("BT", "Voks 2x12"),
            ("TW410", "BM59 4x10"), ("TW110", "Champion 1x8"), ("TW", "TR65 2x12"), ("AT", "TR65 2x12"),
            ("HG", "6505 4x12"), ("CS", "JC120 2x12"), ("Orange", "Tanger 4x12"),
        ]
        guard !name.contains("BC_"), let match = table.first(where: { name.hasPrefix($0.0) }) else { return nil }
        return EffectSlot.cab.models.first { $0.name == match.1 }?.id
    }

    /// The rig's drive pedal, if it has one: the one with the most gain. A boost or overdrive pushes the
    /// amp; a distortion, metal or fuzz pedal pushes it harder.
    static func pedal(_ rig: [String: SongTonesRequest.RigItem]) -> (gear: String, hard: Bool, gain: Double, tone: Double?)? {
        let boosts = ["Pedal_CustomDrive", "Pedal_GermaniumDrive", "Pedal_LineDrive", "Pedal_MarshallGuvnorPlus",
                      "Pedal_RangeBooster", "Pedal_SuperDrive"]
        let hard = ["Pedal_Distortion", "Pedal_MetalDistortion", "Pedal_ShredZone", "Pedal_VintageDistortion",
                    "Pedal_BuzzOne", "Pedal_BuzzToo", "Pedal_CaptFuzzle", "Pedal_FuzzWasHe"]
        return rig.sorted { $0.key < $1.key }.compactMap { _, item -> (gear: String, hard: Bool, gain: Double, tone: Double?)? in
            let isHard = hard.contains(where: item.gear.hasPrefix)
            guard isHard || boosts.contains(where: item.gear.hasPrefix) else { return nil }
            let gain = min(max(item.knobs["Gain"] ?? item.knobs["Boost"] ?? 50, 0), 100)
            return (item.gear, isHard, gain, item.knobs["Tone"])
        }.max { $0.gain < $1.gain }
    }

    // MARK: The match

    /// What Match amps changes in `template` for `tone`, or nil to leave the template as it is.
    static func match(template: ToneDetails, tone: SongTonesRequest.Tone) -> Match? {
        guard let rigAmp = tone.rig["Amp"], let family = Family(gear: rigAmp.gear), let drive = tone.drive,
              !tone.rig.values.contains(where: { $0.gear.hasPrefix("Pedal_AcousticEmulator") }),
              let amp = template.block(.amp).map(KnownBlock.init), !amp.bypassed,
              BandBoxMapping.canSwitchAmp(from: amp.model) else { return nil }
        let cab = template.block(.cab).map(KnownBlock.init)
        let compressor = template.block(.compressor).map(KnownBlock.init)
        let distortion = template.block(.distortion).map(KnownBlock.init)
        guard let was = level(amp: amp, cab: cab, input: input(compressor: compressor, distortion: distortion)) else { return nil }
        var blocks: [Int: KnownBlock] = [:]
        var picked: [String] = []

        // The drive pedal: the rig's, as a Precision Drive; with none, a Precision Drive the template has on goes off.
        var newDistortion = distortion
        if let pedal = pedal(tone.rig) {
            let knob = pedal.hard ? 30 + 0.4 * pedal.gain : 10 + 0.3 * pedal.gain
            newDistortion = KnownBlock(slot: EffectSlot.distortion.rawValue, model: precisionDrive, bypassed: false,
                                       params: [0: Float(knob.rounded()), 1: Float((pedal.tone ?? 50).rounded()), 2: 100])
            picked.append("Precision Drive \(Int(knob.rounded())) for \(pedal.gear)")
        } else if let d = distortion, d.model == precisionDrive, !d.bypassed {
            newDistortion?.bypassed = true
            picked.append("Precision Drive off")
        }
        if let d = newDistortion, d != distortion { blocks[d.slot] = d }
        let u = input(compressor: compressor, distortion: newDistortion)

        // The amp of the family, and the Drive, that is as saturated as the tone's drive asks. Where a
        // stretch of the knob does as well (a clean amp is clean all the way), the game's own gain decides.
        let wanted = target(drive: drive)
        let gain = min(max(rigAmp.knobs["Gain"] ?? rigAmp.knobs.filter { $0.key.hasPrefix("Loudness") }.values.max() ?? 50, 0), 100)
        var best: (model: UInt16, drive: Double, error: Double)?
        // A heavy tone tries the family's hottest amp first, the others its cleanest.
        for model in drive >= 2.0 / 3 ? family.amps.reversed() : family.amps {
            let errors = (0 ... 100).compactMap { d in saturation(model, drive: Double(d), input: u).map { (Double(d), abs($0 - wanted)) } }
            guard let least = errors.map(\.1).min() else { continue }
            let knob = errors.filter { $0.1 <= least + 0.03 }.min { abs($0.0 - gain) < abs($1.0 - gain) }!.0
            if best == nil || least < best!.error - 0.05 { best = (model, knob, least) }    // a hotter amp only if clearly nearer
            if least <= 0.08 { break }      // the first amp that gets there
        }
        guard let best, let defaults = ampDefaults[best.model] else { return nil }

        // The cab: the nearest to the rig's, switched as the template has it.
        var newCab = cab
        if var c = cab, let model = tone.rig["Cabinet"].flatMap({ GearMatch.cab(gear: $0.gear) }), model != c.model {
            c.model = model
            c.params = [:]
            newCab = c
            blocks[c.slot] = c
        }

        // The amp, with the game's tone knobs, and the Volume that keeps the template's level.
        var newAmp = KnownBlock(slot: amp.slot, model: best.model, bypassed: false, params: [:])
        newAmp.params[0] = Float(best.drive)
        for (id, name) in [(UInt8(1), "Bass"), (2, "Mid"), (3, "Treble")] {
            newAmp.params[id] = Float(min(max(rigAmp.knobs[name] ?? defaults[Int(id)], 0), 100).rounded())
        }
        newAmp.params[4] = 50
        guard let at50 = level(amp: newAmp, cab: newCab, input: u) else { return nil }
        let volume = inverse(BandBoxCalibration.volume.map { ($0.knob, $0.dB) }, of: was - at50)
        newAmp.params[4] = Float(min(max(volume, 5), 100).rounded())
        blocks[amp.slot] = newAmp

        let name = EffectSlot.amp.model(best.model)?.name ?? "amp"
        let cabName = newCab.flatMap { EffectSlot.cab.model($0.model)?.name }.map { ", \($0)" } ?? ""
        let short = volume > 100 || volume < 5 ? " (the Volume knob ends there: \(volume > 100 ? "quieter" : "louder") than its slot)" : ""
        let note = "\(rigAmp.gear) gain \(Int(gain)), drive \(String(format: "%.2f", drive)) → \(name) Drive \(Int(best.drive)) "
            + "Volume \(Int(newAmp.params[4]!))\(short)\(cabName)" + (picked.isEmpty ? "" : ", " + picked.joined(separator: ", "))
        return Match(blocks: blocks, note: note)
    }
}
