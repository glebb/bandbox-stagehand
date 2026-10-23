import SwiftUI

/// The controller screens, side by side: a tones page for each guitar channel with a guitar
/// plugged in (channel 3 when there's none), then mix, STEM AI and the preset editor. Swipe (touch, trackpad or drag),
/// tap the dots, or use ← / → to change screen; 1–4 select the tone buttons and 5–9 switch the
/// pedals of the primary guitar channel, Shift+1–9 those of channel 1.
struct ContentView: View {
    @EnvironmentObject private var client: BandBoxClient
    @EnvironmentObject private var assignments: ToneAssignments
    #if os(macOS)
    @EnvironmentObject private var hotKeys: GlobalHotKeys
    @EnvironmentObject private var midi: MIDIInput
    @State private var showMIDI = false
    @State private var midiFlash = false
    #endif
    @State private var page = 0
    @State private var channel = 3
    @State private var editorChannel: Int?   // the guitar channel the preset editor edits; nil = the primary one
    @State private var showLog = false
    @State private var namingBank: BankNaming?
    @State private var confirmDeleteBank = false
    #if os(iOS)
    @State private var confirmQuit = false
    #endif

    private var guitarPages: [Int] { client.activeGuitarChannels }
    private var pageCount: Int { guitarPages.count + 3 }
    private var editorPage: Int { guitarPages.count + 2 }
    private var editedChannel: Int {
        editorChannel.flatMap { guitarPages.contains($0) ? $0 : nil } ?? client.primaryGuitarChannel
    }
    private var connected: Bool { client.link == .connected }

    var body: some View {
        ZStack {
            Stage.background.ignoresSafeArea()

            VStack(spacing: 8) {
                if !connected { linkBanner }
                Pager(page: $page, count: pageCount) { index in
                    if index < guitarPages.count {
                        TonesScreen(channel: guitarPages[index]) { tone in
                            // "Edit Tone…" on a tone button: play it and open it in the editor.
                            let ch = guitarPages[index]
                            if client.presets[ch] != tone { client.setPreset(tone, channel: ch) }
                            editorChannel = ch
                            page = editorPage
                        }
                    } else if index == guitarPages.count {
                        MixScreen(channel: $channel)
                    } else if index == guitarPages.count + 1 {
                        StemScreen()
                    } else {
                        PresetEditorScreen(channel: $editorChannel)
                    }
                }
                // The mix screen starts on the guitar's channel, and follows it when guitars come or go.
                .onChange(of: client.primaryGuitarChannel) { _, guitar in channel = guitar }
                // Keep showing the same screen when a guitar page comes or goes before it.
                .onChange(of: guitarPages) { old, new in
                    if page >= old.count {
                        page += new.count - old.count
                    } else if let i = new.firstIndex(of: old[page]) {
                        page = i
                    } else {
                        page = 0
                    }
                }
                // Usable offline (screens, MIDI, log); dimmed so it's clear nothing reaches the speaker.
                .opacity(connected ? 1 : 0.5)

                footer
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)

        }
        #if os(macOS)
        .frame(minWidth: 760, idealWidth: 900, minHeight: 360, idealHeight: 420)
        #endif
        .background(shortcuts)
        .sheet(isPresented: $showLog) { LogView().environmentObject(client) }
        #if os(macOS)
        .sheet(isPresented: $showMIDI) {
            MIDISheet().environmentObject(midi).environmentObject(client).environmentObject(assignments)
        }
        #endif
    }

    private enum BankNaming: Identifiable {
        case new, rename
        var id: Self { self }
    }

    /// The banks: other sets of the four tone slots. Quiet while there is only one.
    private var bankMenu: some View {
        Menu {
            ForEach(assignments.banks.indices, id: \.self) { i in
                Button { assignments.selectBank(i) } label: {
                    if i == assignments.current { Label(assignments.banks[i].name, systemImage: "checkmark") } else { Text(assignments.banks[i].name) }
                }
            }
            Divider()
            Button("New Bank from Current Slots…") { namingBank = .new }
            Button("Rename \(assignments.bankName)…") { namingBank = .rename }
            if assignments.banks.count > 1 {
                Button("Delete \(assignments.bankName)…", role: .destructive) { confirmDeleteBank = true }
            }
        } label: {
            Text(assignments.banks.count > 1 ? "Bank: \(assignments.bankName)" : "Banks")
                .foregroundStyle(assignments.banks.count > 1 ? Stage.secondaryText : Stage.faintText)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .sheet(item: $namingBank) { naming in
            NameSheet(title: naming == .new ? "New Bank" : "Rename Bank",
                      name: naming == .new ? "" : assignments.bankName,
                      action: naming == .new ? "Create" : "Rename") { name in
                if naming == .new { assignments.addBank(named: name) } else { assignments.renameBank(to: name) }
            }
        }
        .confirmationDialog("Delete the bank \(assignments.bankName)?", isPresented: $confirmDeleteBank, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { assignments.deleteBank() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its slots are lost. The tones on the speaker stay.")
        }
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(0 ..< pageCount, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Stage.text : Stage.dot)
                        .frame(width: 6, height: 6)
                        .padding(4)
                        .contentShape(Rectangle())
                        .onTapGesture { page = i }
                }
            }
            // Which guitar channel a tones page controls, just left of the dots so they stay centred.
            .overlay(alignment: .leading) {
                if let ch = page < guitarPages.count ? guitarPages[page] : (page == editorPage ? editedChannel : nil) {
                    Text("CH \(ch)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Stage.secondaryText)
                        .fixedSize()
                        .padding(.trailing, 10)
                        .frame(width: 0, alignment: .trailing)   // grows leftwards from the dots
                }
            }
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(client.deviceName ?? "JBL BandBox Trio")
                Spacer()
                if let battery = client.battery {
                    HStack(spacing: 3) {
                        if client.externalPower { Image(systemName: "bolt.fill").font(.system(size: 9)) }
                        Text("\(battery)%").monospacedDigit()
                    }
                    .help(client.externalPower ? "Battery \(battery)%, on the wall power" : "Battery \(battery)%")
                }
                #if os(macOS)
                // While on, 1–9 work from any app (and stop typing digits elsewhere).
                Button { hotKeys.enabled.toggle() } label: {
                    Text(hotKeys.enabled ? "Keys 1–9: everywhere" : "Keys 1–9: in app")
                        .foregroundStyle(hotKeys.enabled ? Stage.amber : Stage.faintText)
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                .help("When on, 1–4 select tones and 5–9 switch pedals while other apps are in front (Shift for channel 1).")
                // The dot flashes amber on each incoming message.
                Button { showMIDI = true } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(midiFlash ? Stage.amber : midi.enabled && !midi.sources.isEmpty ? Stage.secondaryText : Stage.dot)
                            .frame(width: 5, height: 5)
                        Text(midi.enabled ? "MIDI" : "MIDI off")
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 10)
                .help("MIDI control: which messages select tones and switch pedals.")
                .onChange(of: midi.messageCount) {
                    midiFlash = true
                    withAnimation(.easeOut(duration: 0.3).delay(0.1)) { midiFlash = false }
                }
                #endif
                bankMenu
                    .padding(.leading, 10)
                Button("Log") { showLog = true }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
                #if os(iOS)
                // Out of the way at the end of the footer, and asks first: a stray tap mid-song does nothing.
                Button("Quit") { confirmQuit = true }
                    .buttonStyle(.plain)
                    .padding(.leading, 16)
                    .confirmationDialog("Quit Stagehand?", isPresented: $confirmQuit, titleVisibility: .visible) {
                        Button("Quit", role: .destructive) {
                            // Let go of the speaker first, so the JBL app can connect.
                            client.disconnect()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(0) }
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Disconnects from the speaker and closes the app.")
                    }
                #endif
            }
            .font(.system(size: 11))
            .foregroundStyle(Stage.faintText)
            .padding(.horizontal, 4)
        }
        .frame(height: 14)
    }

    /// Why there's no speaker, with Cancel while it searches and Connect once stopped.
    private var linkBanner: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 8, height: 8)
            Text(statusText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Stage.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            switch client.link {
            case .searching, .connecting:
                Button("Cancel") { client.disconnect() }
            case .offline:
                Button("Connect") { client.connect() }
            default:
                EmptyView()
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(Stage.amber)
        .padding(.horizontal, 14)
        .frame(height: 36)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Stage.tile))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Stage.tileBorder, lineWidth: 1))
    }

    /// Invisible buttons that carry the keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("") { page = max(page - 1, 0) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { page = min(page + 1, pageCount - 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            // 1–4 select the tone buttons and 5–9 switch the pedals; Shift for channel 1.
            ForEach(Array(StageAction.all.enumerated()), id: \.element) { i, action in
                let perChannel = ToneSlot.all.count + Pedal.allCases.count
                Button("") { client.perform(action, assignments: assignments) }
                    .keyboardShortcut(KeyEquivalent(Character("\(i % perChannel + 1)")),
                                      modifiers: i < perChannel ? [] : .shift)
            }
        }
        .opacity(0)
        .accessibilityHidden(true)
    }

    private var statusText: String {
        switch client.link {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .offline: "Not connected to the speaker"
        case .searching: "Searching… (close the JBL app on your phone)"
        case .bluetoothOff: "Bluetooth is off"
        #if os(macOS)
        case .unauthorized: "Bluetooth permission needed (System Settings › Privacy)"
        #else
        case .unauthorized: "Bluetooth permission needed (Settings › BandBox)"
        #endif
        }
    }

    private var statusColor: Color {
        switch client.link {
        case .connected: .green
        case .connecting, .searching: .orange
        case .bluetoothOff, .unauthorized: .red
        case .offline: Stage.dot
        }
    }
}

/// Lays its pages out in a row and shows one. A horizontal drag or trackpad swipe of
/// enough distance moves one page; taps on the pages still go through.
struct Pager<Content: View>: View {
    @Binding var page: Int
    let count: Int
    @ViewBuilder let content: (Int) -> Content
    @GestureState private var drag: CGFloat = 0
    #if os(macOS)
    @State private var swipe = TrackpadSwipe()
    #endif

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(0 ..< count, id: \.self) { i in
                    content(i)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // The whole page takes the swipe, also its gaps and switched-off controls.
                        .contentShape(Rectangle())
                }
            }
            .frame(width: geo.size.width * CGFloat(count), alignment: .leading)
            .offset(x: -CGFloat(page) * geo.size.width + drag)
            .animation(.easeOut(duration: 0.25), value: page)
            .simultaneousGesture(
                DragGesture(minimumDistance: 30)
                    .updating($drag) { value, state, _ in
                        let t = value.translation
                        state = abs(t.width) > abs(t.height) ? t.width / 3 : 0
                    }
                    .onEnded { value in
                        // Mostly sideways only, so turning a knob (up and down) doesn't change page.
                        let t = value.translation
                        if abs(t.width) > 60, abs(t.width) > abs(t.height) * 1.5 { turn(t.width < 0 ? 1 : -1) }
                    })
        }
        .clipped()
        #if os(macOS)
        .onAppear { swipe.start { turn($0) } }
        .onDisappear { swipe.stop() }
        #endif
    }

    private func turn(_ step: Int) {
        page = min(max(page + step, 0), count - 1)
    }
}

struct LogView: View {
    @EnvironmentObject private var client: BandBoxClient
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(client.log.enumerated()), id: \.offset) { i, line in
                            Text(line).id(i)
                        }
                    }
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { proxy.scrollTo(client.log.count - 1, anchor: .bottom) }
                .onChange(of: client.log.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(14)
        #if os(macOS)
        .frame(width: 640, height: 400)
        #endif
    }
}
