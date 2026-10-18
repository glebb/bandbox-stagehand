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
                .allowsHitTesting(connected)
                .opacity(connected ? 1 : 0.4)

                footer
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)

            if !connected {
                Label(statusText, systemImage: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Stage.text)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Stage.tile))
                    .overlay(Capsule().strokeBorder(Stage.tileBorder, lineWidth: 1))
            }
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
                    Text("\(battery)%").monospacedDigit()
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
                Button("Log") { showLog = true }
                    .buttonStyle(.plain)
                    .padding(.leading, 10)
            }
            .font(.system(size: 11))
            .foregroundStyle(Stage.faintText)
            .padding(.horizontal, 4)
        }
        .frame(height: 14)
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
                    content(i).frame(width: geo.size.width, height: geo.size.height)
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
