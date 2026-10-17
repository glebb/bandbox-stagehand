import SwiftUI

/// The three controller screens, side by side. Swipe (touch, trackpad or drag), tap the dots,
/// or use ← / → to change screen; 1–4 select the tone buttons.
struct ContentView: View {
    @EnvironmentObject private var client: BandBoxClient
    @EnvironmentObject private var assignments: ToneAssignments
    @State private var page = 0
    @State private var channel = 3
    @State private var showLog = false

    private static let pageCount = 3
    private var connected: Bool { client.link == .connected }

    var body: some View {
        ZStack {
            Stage.background.ignoresSafeArea()

            VStack(spacing: 8) {
                Pager(page: $page, count: Self.pageCount) { index in
                    switch index {
                    case 0: TonesScreen()
                    case 1: MixScreen(channel: $channel)
                    default: StemScreen()
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
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 6) {
                ForEach(0 ..< Self.pageCount, id: \.self) { i in
                    Circle()
                        .fill(i == page ? Stage.text : Stage.dot)
                        .frame(width: 6, height: 6)
                        .padding(4)
                        .contentShape(Rectangle())
                        .onTapGesture { page = i }
                }
            }
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 6, height: 6)
                Text(client.deviceName ?? "JBL BandBox Trio")
                Spacer()
                if let battery = client.battery {
                    Text("\(battery)%").monospacedDigit()
                }
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
            Button("") { page = min(page + 1, Self.pageCount - 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            ForEach(ToneSlot.all) { slot in
                Button("") { if connected { client.setPreset(assignments.tones[slot.id]) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(slot.id + 1)")), modifiers: [])
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
                    .updating($drag) { value, state, _ in state = value.translation.width / 3 }
                    .onEnded { value in
                        if abs(value.translation.width) > 60 { turn(value.translation.width < 0 ? 1 : -1) }
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
