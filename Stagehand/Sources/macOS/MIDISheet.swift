import SwiftUI

/// MIDI settings: on or off, the connected sources, and what each tone button and pedal
/// listens to. Click a binding, then press the switch, to learn it.
struct MIDISheet: View {
    @EnvironmentObject private var midi: MIDIInput
    @EnvironmentObject private var client: BandBoxClient
    @EnvironmentObject private var assignments: ToneAssignments
    @EnvironmentObject private var songTones: ScratchFiller
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Toggle("Listen to MIDI", isOn: $midi.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13, weight: .medium))
                Text(midi.sources.isEmpty ? "No MIDI devices or apps found yet" : "From " + midi.sources.joined(separator: ", "))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help("MIDI devices and apps are picked up as they appear.")
                Spacer()
                Text(midi.lastMessage.map { "Last: \($0.label)" } ?? "Nothing received yet")
                    .monospacedDigit()
            }
            .foregroundStyle(Stage.secondaryText)

            HStack(alignment: .top, spacing: 28) {
                // Like the keys: plain 1–9 for the main guitar channel, Shift for channel 1.
                column(.primary, title: "Guitar channel (CH 3, or CH 1 if it's the only guitar)")
                column(.channel1, title: "Channel 1")
            }
            .opacity(midi.enabled ? 1 : 0.5)

            Divider()
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Toggle("Song tones", isOn: $songTones.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Stage.secondaryText)
                Text("Another app (e.g. the RS Companion for Rocksmith) can describe a song's tones in a SysEx "
                     + "message: Stagehand makes a tone for each from your slots, in up to five tones of its own "
                     + "(Song 1–5), and the Program Changes the message names play them.")
                    .font(.system(size: 11))
                    .foregroundStyle(Stage.faintText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .opacity(midi.enabled ? 1 : 0.5)

            HStack {
                Button("Reset to Defaults") { midi.resetToDefaults() }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Click a binding, then press the switch or key.")
                    if client.primaryGuitarChannel == 1 {
                        Text("Only channel 1 has a guitar, so both columns control it.")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Stage.faintText)
                .padding(.leading, 8)
                Spacer()
                Button("Done") {
                    midi.learning = nil
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 720)
        .onExitCommand { if midi.learning != nil { midi.learning = nil } else { dismiss() } }
    }

    private func column(_ target: ChannelTarget, title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Stage.secondaryText)
                .padding(.bottom, 2)
            ForEach(StageAction.all.filter { $0.target == target }, id: \.self) { row($0) }
        }
        .frame(maxWidth: .infinity)
    }

    private func row(_ action: StageAction) -> some View {
        let binding = midi.binding(for: action)
        let learning = midi.learning == action
        return HStack(spacing: 8) {
            Text(name(action))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { midi.learning = learning ? nil : action } label: {
                Text(learning ? "Press a switch…" : binding?.trigger.label ?? "Learn")
                    .monospacedDigit()
                    .foregroundStyle(learning ? Stage.amber : binding == nil ? Stage.faintText : Stage.text)
                    .frame(width: 118, height: 20)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(learning ? Stage.amberTint : Stage.tile))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(learning ? Stage.amberBorder : Stage.tileBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(learning ? "Click again to cancel." : "Click, then press the switch or key to use for this.")
            if let binding, binding.trigger.kind == .control, case .pedal = action {
                Text(binding.mode == .auto ? "Auto" : "Follow")
                    .font(.system(size: 10))
                    .foregroundStyle(Stage.mutedText)
                    .frame(width: 34, alignment: .leading)
            } else {
                Spacer().frame(width: 34)
            }
            menu(action, binding)
        }
        .frame(height: 22)
    }

    private func menu(_ action: StageAction, _ binding: MIDIBinding?) -> some View {
        Menu {
            Picker("MIDI Channel", selection: Binding(get: { binding?.trigger.channel ?? -1 },
                                                      set: { midi.setChannel($0 < 0 ? nil : $0, for: action) })) {
                Text("Any").tag(-1)
                ForEach(0 ..< 16, id: \.self) { Text("\($0 + 1)").tag($0) }
            }
            if binding?.trigger.kind == .control, case .pedal = action {
                Picker("Switch", selection: Binding(get: { binding?.mode ?? .auto },
                                                    set: { midi.setMode($0, for: action) })) {
                    Text("Auto (momentary or latching)").tag(PedalMode.auto)
                    Text("Follow (64 and up is on)").tag(PedalMode.follow)
                }
            }
            Divider()
            Button("Clear") { midi.clear(action) }
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20)
        .disabled(binding == nil)
    }

    private func name(_ action: StageAction) -> String {
        switch action {
        case let .tone(slot, target):
            "\(slot + 1) · " + assignments.name(ToneSlot.all[slot], channel: target.channel(client))
        case let .pedal(pedal, _):
            pedal.name
        }
    }
}
