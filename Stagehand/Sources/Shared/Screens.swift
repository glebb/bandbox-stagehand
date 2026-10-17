import SwiftUI

// The controller's three screens, laid out for a landscape window or phone:
// 1. tones and pedals, 2. tuner and mix, 3. STEM AI.

struct TonesScreen: View {
    @EnvironmentObject private var client: BandBoxClient
    @EnvironmentObject private var assignments: ToneAssignments
    @State private var assigning: Int?
    @State private var choosingModel: Pedal?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                ForEach(Pedal.allCases) { pedalButton($0) }
            }
            .frame(height: 50)

            HStack(spacing: 10) {
                ForEach(ToneSlot.all) { toneButton($0) }
            }
        }
    }

    /// Tap switches the pedal on or off; long-press (or right-click) picks its model.
    private func pedalButton(_ pedal: Pedal) -> some View {
        let on = client.isOn(pedal)
        let switchable = pedal.models.count > 1 && on != nil
        return SwitchPad(on: on == true,
                         longPress: switchable ? { choosingModel = pedal } : nil,
                         action: { if let on { client.setPedal(pedal, on: !on) } }) {
            Text(pedal.name).font(.system(size: 13, weight: .medium))
        }
        .opacity(on == nil ? 0.4 : 1)
        #if os(macOS)
        .contextMenu {
            if switchable {
                ForEach(pedal.models) { model in
                    Button { client.setModel(pedal, model) } label: {
                        if client.model(pedal) == model.id { Label(model.name, systemImage: "checkmark") } else { Text(model.name) }
                    }
                }
            }
        }
        #endif
        .popover(isPresented: Binding(get: { choosingModel == pedal },
                                      set: { if !$0 { choosingModel = nil } })) {
            ModelPicker(pedal: pedal, current: client.model(pedal)) {
                client.setModel(pedal, $0)
                choosingModel = nil
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func toneButton(_ slot: ToneSlot) -> some View {
        let toneID = assignments.tones[slot.id]
        let selected = client.preset == toneID
        return Pad(fill: selected ? slot.tint : Stage.toneTile,
                   border: selected ? slot.color : Stage.toneBorder,
                   borderWidth: selected ? 1.5 : 1,
                   longPress: { assigning = slot.id },
                   action: { client.setPreset(toneID) }) {
            VStack(spacing: 10) {
                Text(slot.name)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(selected ? slot.color : Stage.text)
                Text(toneName(toneID))
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? Stage.control : Stage.mutedText)
                    .lineLimit(1)
            }
            .padding(.vertical, 6)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 2, bottomTrailingRadius: 2)
                .fill(slot.color)
                .frame(width: 28, height: 3)
                .allowsHitTesting(false)
        }
        #if os(macOS)
        // Right-click as well as hold; on the iPhone a long press already opens the picker.
        .contextMenu {
            Button("Save Pedals to \(toneName(toneID))") { client.saveTone() }
                .disabled(!selected || client.toneDetails?.id != toneID)
            Divider()
            toneMenu { assignments.assign($0, to: slot.id) }
        }
        #endif
        .popover(isPresented: Binding(get: { assigning == slot.id },
                                      set: { if !$0 { assigning = nil } })) {
            TonePicker(title: "\(slot.name) button", current: toneID) {
                assignments.assign($0, to: slot.id)
                client.setPreset($0)
                assigning = nil
            } header: {
                saveRow(toneID)
            }
            .presentationCompactAdaptation(.popover)
        }
    }

    private func toneName(_ id: Int) -> String {
        client.tones.first { $0.id == id }?.name ?? "Tone #\(id)"
    }

    /// Saves the pedals as they are now into the button's tone on the speaker.
    /// Only for the playing tone: the pedal states are the speaker's, for that tone.
    private func saveRow(_ toneID: Int) -> some View {
        let ready = client.preset == toneID && client.toneDetails?.id == toneID
        let on = Pedal.allCases.filter { client.isOn($0) == true }.map(\.name)
        return Button {
            client.saveTone()
            assigning = nil
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Save pedals to \(toneName(toneID))")
                    Text(ready ? (on.isEmpty ? "All pedals off" : on.joined(separator: ", "))
                               : "Select this tone first")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "square.and.arrow.down")
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!ready)
        .opacity(ready ? 1 : 0.4)
    }

    @ViewBuilder
    private func toneMenu(_ pick: @escaping (Int) -> Void) -> some View {
        ForEach(client.groupedTones, id: \.category) { group in
            Section(group.category) {
                ForEach(group.tones) { tone in
                    Button(tone.name) { pick(tone.id) }
                }
            }
        }
    }
}

/// The models a pedal can use in the current tone; picking one swaps it in.
struct ModelPicker: View {
    let pedal: Pedal
    let current: UInt16?
    let pick: (PedalModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("\(pedal.name) pedal").font(.headline).padding(12)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(pedal.models) { model in
                        Button { pick(model) } label: {
                            HStack {
                                Text(model.name)
                                Spacer()
                                if model.id == current { Image(systemName: "checkmark") }
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
        .frame(width: 220, height: min(CGFloat(pedal.models.count) * 30 + 70, 380))
    }
}

/// Every tone in the speaker's library, grouped by category; picking one assigns it.
/// `header` goes between the title and the list.
struct TonePicker<Header: View>: View {
    @EnvironmentObject private var client: BandBoxClient
    let title: String
    let current: Int
    let pick: (Int) -> Void
    @ViewBuilder var header: () -> Header

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(12)
            Divider()
            header()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(client.groupedTones, id: \.category) { group in
                        Text(group.category)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 10)
                        ForEach(group.tones) { tone in
                            Button { pick(tone.id) } label: {
                                HStack {
                                    Text(tone.name)
                                    Spacer()
                                    if tone.id == current { Image(systemName: "checkmark") }
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
        }
        .frame(width: 260, height: 440)
    }
}

struct MixScreen: View {
    @EnvironmentObject private var client: BandBoxClient
    @Binding var channel: Int

    var body: some View {
        HStack(spacing: 10) {
            TunerPad()
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            VolumeColumn(level: client.channelVolume(channel)) {
                client.changeChannelVolume(channel, by: $0)
            } header: {
                Segmented(options: Array(BandBoxClient.channels), selected: channel,
                          enabled: { client.channelVolume($0) != nil }) { channel = $0 }
            }
            .frame(width: 160)
            VolumeColumn(title: "Master", level: client.masterVolume) {
                client.changeMasterVolume(by: $0)
            }
            .frame(width: 160)
        }
    }
}

/// Tap to turn the tuner on or off. Shows the note it hears and how far off it is.
struct TunerPad: View {
    @EnvironmentObject private var client: BandBoxClient

    var body: some View {
        Pad(border: client.tunerOn ? Stage.tunerBorder : Stage.tileBorder,
            action: { client.setTuner(!client.tunerOn) }) {
            VStack(spacing: 0) {
                if !client.tunerOn {
                    Text("Tuner").font(.system(size: 20, weight: .medium)).foregroundStyle(Stage.text)
                    Text("Tap to turn on").font(.system(size: 12)).foregroundStyle(Stage.secondaryText)
                        .padding(.top, 10)
                } else {
                    let reading = client.tuner.flatMap { $0.hasSignal ? $0 : nil }
                    let cents = reading.map { Int($0.cents.rounded()) }
                    let inTune = cents.map { abs($0) < 5 } ?? false
                    Text(reading?.noteName ?? "–")
                        .font(.system(size: 56, weight: .medium))
                        .foregroundStyle(inTune ? Stage.inTune : (reading == nil ? Stage.faintText : Stage.text))
                        .frame(height: 60)
                    TunerTicks(cents: reading?.cents)
                        .frame(height: 18)
                        .padding(.top, 18)
                    Text(cents.map { "\($0 > 0 ? "+" : $0 < 0 ? "−" : "")\(abs($0)) cents" } ?? "Play a string")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Stage.secondaryText)
                        .padding(.top, 10)
                    Text(client.tunerReference.map { String(format: "%.0f Hz", $0) } ?? "440 Hz")
                        .font(.system(size: 12))
                        .foregroundStyle(Stage.faintText)
                        .padding(.top, 6)
                }
            }
        }
    }
}

/// 21 ticks from −50 to +50 cents in 5-cent steps; the one nearest the reading lights up,
/// green within 5 cents of pitch, amber otherwise.
struct TunerTicks: View {
    let cents: Float?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0 ..< 21, id: \.self) { i in
                let value = Float(i - 10) * 5
                let hit = cents.map { abs(value - min(max($0, -50), 50)) <= 2.5 } ?? false
                let inTune = cents.map { abs($0) < 5 } ?? false
                Capsule()
                    .fill(hit ? (inTune ? Stage.inTune : Stage.amber) : (i == 10 ? Stage.tick : Stage.meterTrack))
                    .frame(width: 3, height: i == 10 ? 18 : 11)
            }
        }
        .animation(.easeOut(duration: 0.1), value: cents)
    }
}

struct StemScreen: View {
    @EnvironmentObject private var client: BandBoxClient

    private var stemOn: Bool { client.stemAI ?? false }

    var body: some View {
        HStack(spacing: 10) {
            SwitchPad(on: stemOn, action: { client.setStemAI(!stemOn) }) {
                VStack(spacing: 8) {
                    Text("STEM AI").font(.system(size: 20, weight: .medium))
                    Text(stemOn ? "On" : "Off").font(.system(size: 12)).opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity)

            Group {
                stemColumn(1)
                stemColumn(2)
                VolumeColumn(title: "Others", level: client.stemLevels[3]) {
                    client.changeStemVolume(3, by: $0)
                }
            }
            .frame(width: 150)
            .opacity(stemOn ? 1 : 0.4)
            .allowsHitTesting(stemOn)
        }
    }

    private func stemColumn(_ channel: Int) -> some View {
        let type = client.stemTypes[channel] ?? .off
        return VolumeColumn(level: type == .off ? nil : client.stemLevels[channel]) {
            if type != .off { client.changeStemVolume(channel, by: $0) }
        } header: {
            Menu {
                ForEach(StemType.allCases) { option in
                    Button(option.name) { client.setStemType(channel, option) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(type.name)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12))
                .foregroundStyle(Stage.stemType)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        }
    }
}

extension BandBoxClient {
    /// The tone library grouped by category, in the speaker's order.
    var groupedTones: [(category: String, tones: [Tone])] {
        var order: [Int] = []
        var byCategory: [Int: [Tone]] = [:]
        for tone in tones {
            if byCategory[tone.categoryID] == nil { order.append(tone.categoryID) }
            byCategory[tone.categoryID, default: []].append(tone)
        }
        return order.map { (categories[$0] ?? "Category \($0)", byCategory[$0] ?? []) }
    }
}
