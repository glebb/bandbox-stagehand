import SwiftUI

// The preset editor: a tone's whole chain, each slot's model and knobs, saved over the tone
// or as a new one. It edits the tone a guitar channel plays (edits apply to that tone), so
// choosing another tone from its name plays it. A tone button's "Edit…" opens it on that tone.

/// The editor page, for guitar channel `channel` (the primary guitar channel until one is
/// chosen, or when the chosen one has no guitar any more).
struct PresetEditorScreen: View {
    @Binding var channel: Int?
    @EnvironmentObject private var client: BandBoxClient

    var body: some View {
        let ch = channel.flatMap { client.activeGuitarChannels.contains($0) ? $0 : nil } ?? client.primaryGuitarChannel
        if client.toneDetails[ch] != nil {
            PresetEditor(channel: ch) { channel = $0 }
        } else {
            Text("Waiting for the speaker…")
                .font(.system(size: 13))
                .foregroundStyle(Stage.mutedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The editor for the tone guitar channel `channel` plays.
struct PresetEditor: View {
    let channel: Int
    let switchChannel: (Int) -> Void
    @EnvironmentObject private var client: BandBoxClient
    @EnvironmentObject private var assignments: ToneAssignments
    @State private var selected: EffectSlot = .amp
    @State private var choosingTone = false
    @State private var pendingTone: Int?          // a tone chosen while there are unsaved edits
    @State private var savingAs = false
    @State private var renaming = false
    @State private var confirm: Confirm?
    @State private var assigning: CreatedTone?    // a new tone to offer for a button

    private enum Confirm: Identifiable {
        case delete, reset
        var id: Self { self }
    }

    private var details: ToneDetails? { client.toneDetails[channel] }
    private var tone: Tone? { client.tones.first { $0.id == details?.id } }
    private var edited: Bool { client.isEdited(channel: channel) }

    var body: some View {
        VStack(spacing: 10) {
            header.frame(height: 32)
            chain.frame(height: 62)
            panel
        }
        .confirmationDialog("Unsaved changes to \(details?.name ?? "this tone")",
                            isPresented: Binding(get: { pendingTone != nil }, set: { if !$0 { pendingTone = nil } }),
                            titleVisibility: .visible) {
            Button("Save, then switch") {
                client.saveTone(channel: channel)
                if let pendingTone { client.setPreset(pendingTone, channel: channel) }
            }
            Button("Save as New Tone…") { pendingTone = nil; savingAs = true }
            Button("Discard Changes", role: .destructive) {
                if let pendingTone { client.setPreset(pendingTone, channel: channel) }
            }
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            titleVisibility: .visible) {
            if let id = details?.id {
                switch confirm {
                case .delete: Button("Delete", role: .destructive) { client.deleteTone(id, channel: channel) }
                case .reset: Button("Reset", role: .destructive) { client.resetTone(id, channel: channel) }
                case nil: EmptyView()
                }
            }
        }
        .sheet(item: $assigning) { created in
            AssignSheet(toneID: created.id, channel: channel)
                .environmentObject(client)
                .environmentObject(assignments)
        }
        .sheet(isPresented: $savingAs) {
            if let details {
                SaveAsSheet(name: details.name, category: tone?.categoryID ?? 0) { name, category in
                    client.saveToneAs(name, category: category, channel: channel)
                }
                .environmentObject(client)
            }
        }
        .sheet(isPresented: $renaming) {
            if let details {
                NameSheet(title: "Rename Tone", name: details.name, action: "Rename") {
                    client.renameTone(details.id, to: $0, channel: channel)
                }
            }
        }
        .onChange(of: client.createdTone) { _, created in
            if let created, created.channel == channel { assigning = created }
        }
    }

    private var confirmTitle: String {
        let name = details?.name ?? "this tone"
        switch confirm {
        case .delete: return "Delete \(name) from the speaker?"
        case .reset: return "Put \(name) back to its factory settings? Its saved changes are lost."
        case nil: return ""
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Button { choosingTone = true } label: {
                HStack(spacing: 6) {
                    Text(details?.name ?? "–")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Stage.text)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Stage.secondaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $choosingTone) {
                TonePicker(title: "Edit tone", current: details?.id ?? 0) { id in
                    choosingTone = false
                    guard id != details?.id else { return }
                    if edited { pendingTone = id } else { client.setPreset(id, channel: channel) }
                } header: { EmptyView() }
                .presentationCompactAdaptation(.popover)
            }

            if edited {
                Text("Edited")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Stage.amber)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Stage.amberTint))
                    .overlay(Capsule().strokeBorder(Stage.amberBorder, lineWidth: 1))
            }

            Spacer()

            // With guitars in both channels: which one's tone to edit.
            if client.activeGuitarChannels.count > 1 {
                Segmented(options: client.activeGuitarChannels, selected: channel, label: { "CH \($0)" },
                          pick: switchChannel)
                    .frame(width: 110, height: 28)
            }

            Menu {
                Button("Discard Changes") { client.discardEdits(channel: channel) }.disabled(!edited)
                Button("Rename…") { renaming = true }.disabled(tone?.isUser != true)
                if tone?.isUser == true {
                    Button("Delete…", role: .destructive) { confirm = .delete }
                } else {
                    Button("Reset to Factory…") { confirm = .reset }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Stage.control)
            }
            .menuIndicator(.hidden)
            .fixedSize()

            headerButton("Save as…", prominent: false) { savingAs = true }
            headerButton("Save", prominent: edited) { client.saveTone(channel: channel) }
                .disabled(!edited)
                .opacity(edited ? 1 : 0.4)
        }
    }

    private func headerButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(prominent ? Stage.amber : Stage.text)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(Capsule().fill(prominent ? Stage.amberTint : Stage.tile))
                .overlay(Capsule().strokeBorder(prominent ? Stage.amberBorder : Stage.tileBorder, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Chain

    /// The eight slots in signal order, joined by a cable; tap one to edit it.
    private var chain: some View {
        HStack(spacing: 6) {
            ForEach(EffectSlot.allCases) { slot in
                slotTile(slot)
            }
        }
        .background(Rectangle().fill(Stage.tick).frame(height: 2))
    }

    private func slotTile(_ slot: EffectSlot) -> some View {
        let block = client.block(slot, channel: channel)
        let on = block.map { !$0.bypassed } ?? false
        let isSelected = slot == selected
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(spacing: 3) {
            Text(slot.name.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? Stage.text : Stage.mutedText)
            Text(block.flatMap { slot.model($0.model)?.name } ?? "–")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Stage.amber : Stage.mutedText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(shape.fill(on ? Stage.amberTint : Stage.tile))
        .overlay(shape.strokeBorder(isSelected ? Stage.text : (on ? Stage.amberBorder : Stage.tileBorder),
                                    lineWidth: isSelected ? 1.5 : 1))
        .contentShape(shape)
        .onTapGesture { selected = slot }
    }

    // MARK: Slot panel

    @ViewBuilder
    private var panel: some View {
        let block = client.block(selected, channel: channel)
        let model = block.flatMap { selected.model($0.model) }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // Amp and cab are always in the chain in the JBL app; no bypass for them.
                if let block, selected != .amp, selected != .cab {
                    SwitchPad(on: !block.bypassed, action: {
                        client.setBypass(selected, on: block.bypassed, channel: channel)
                    }) {
                        Image(systemName: "power").font(.system(size: 15, weight: .semibold))
                    }
                    .frame(width: 52, height: 34)
                }
                modelChips(current: block?.model)
            }
            .frame(height: 34)

            if let block, let model {
                knobs(block, model)
            } else if let block {
                // A model missing from the catalog: still show its knobs by ID.
                knobs(block, EffectModel(block.model, String(format: "Model %04x", block.model),
                                         block.params.map { ParamSpec(id: $0.id, name: "P\($0.id)") }))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func modelChips(current: UInt16?) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selected.models) { model in
                        let isCurrent = model.id == current
                        Button {
                            if !isCurrent { client.setModel(selected, model, channel: channel) }
                        } label: {
                            Text(model.name)
                                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                                .foregroundStyle(isCurrent ? Stage.text : Stage.secondaryText)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .background(Capsule().fill(isCurrent ? Stage.segmentSelected : Stage.tile))
                                .overlay(Capsule().strokeBorder(isCurrent ? Stage.control : Stage.tileBorder, lineWidth: 1))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .id(model.id)
                    }
                }
            }
            .onAppear { if let current { proxy.scrollTo(current, anchor: .center) } }
            .onChange(of: selected) { _, _ in if let current { proxy.scrollTo(current, anchor: .center) } }
        }
    }

    @ViewBuilder
    private func knobs(_ block: EffectBlock, _ model: EffectModel) -> some View {
        if model.params.isEmpty {
            Text(selected == .cab ? "Cabinets have no knobs." : "No knobs.")
                .font(.system(size: 13))
                .foregroundStyle(Stage.mutedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                if let category = model.category {
                    Text(category)
                        .font(.system(size: 11))
                        .foregroundStyle(Stage.secondaryText)
                }
                HStack(alignment: .top, spacing: 18) {
                    ForEach(model.params) { spec in
                        if let value = block.value(spec.id) {
                            Knob(spec: spec, value: value, size: spec.small ? 62 : 78) {
                                client.setParam(selected, spec.id, to: $0, channel: channel)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(block.bypassed ? 0.5 : 1)
        }
    }
}

/// After a save as: the channel's four tone buttons, to put the new tone on one, or none.
struct AssignSheet: View {
    let toneID: Int
    let channel: Int
    @EnvironmentObject private var client: BandBoxClient
    @EnvironmentObject private var assignments: ToneAssignments
    @Environment(\.dismiss) private var dismiss

    private func toneName(_ id: Int) -> String { client.tones.first { $0.id == id }?.name ?? "Tone #\(id)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Put \(toneName(toneID)) on a tone button?").font(.headline)
            HStack(spacing: 8) {
                ForEach(ToneSlot.all) { slot in
                    Pad(fill: slot.tint, border: slot.color, action: {
                        assignments.assign(toneID, to: slot.id, channel: channel)
                        dismiss()
                    }) {
                        VStack(spacing: 6) {
                            Text(assignments.name(slot, channel: channel))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(slot.color)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Text("now \(toneName(assignments.tone(slot, channel: channel)))")
                                .font(.system(size: 11))
                                .foregroundStyle(Stage.control)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .frame(width: 120, height: 76)
                }
            }
            HStack {
                Spacer()
                Button("Don't Add") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .background(Stage.background)
        .preferredColorScheme(.dark)
    }
}

/// Save as: a name for the new tone (starting from the current one) and its category.
struct SaveAsSheet: View {
    @EnvironmentObject private var client: BandBoxClient
    @Environment(\.dismiss) private var dismiss
    @State var name: String
    @State var category: Int
    let save: (String, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Save as New Tone").font(.headline)
            NameField(name: $name)
            Picker("Category", selection: $category) {
                ForEach(client.categories.keys.sorted(), id: \.self) { id in
                    Text(client.categories[id] ?? "\(id)").tag(id)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(NameField.clean(name), category)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(NameField.clean(name).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}

/// A sheet asking for a tone name (rename).
struct NameSheet: View {
    let title: String
    @State var name: String
    let action: String
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            NameField(name: $name)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(action) {
                    done(NameField.clean(name))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(NameField.clean(name).isEmpty)
            }
        }
        .padding(20)
        .frame(minWidth: 320)
    }
}

/// A tone name: the speaker's names are plain ASCII; 20 characters is a guess at its limit,
/// which isn't known.
struct NameField: View {
    @Binding var name: String
    static let maxLength = 20

    static func clean(_ s: String) -> String {
        String(s.unicodeScalars.filter { $0.isASCII && $0.value >= 0x20 }.map(Character.init).prefix(maxLength))
            .trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        TextField("Name", text: $name)
            .textFieldStyle(.roundedBorder)
            .onChange(of: name) { _, new in
                if new.count > Self.maxLength { name = String(new.prefix(Self.maxLength)) }
            }
    }
}
