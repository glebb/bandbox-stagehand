import SwiftUI

/// The controller with the splash screen over it until the speaker connects (at most 10 s).
struct RootView: View {
    @EnvironmentObject private var client: BandBoxClient
    @State private var splash = true

    private static let maxSplash: Duration = .seconds(10)

    var body: some View {
        ZStack {
            ContentView()
            if splash {
                SplashView().transition(.opacity)
            }
        }
        .task {
            try? await Task.sleep(for: Self.maxSplash)
            hideSplash()
        }
        .onChange(of: client.link) { _, link in
            // Done connecting, or nothing to wait for: the controller explains Bluetooth problems.
            if link != .searching && link != .connecting { hideSplash() }
        }
    }

    private func hideSplash() {
        withAnimation(.easeOut(duration: 0.4)) { splash = false }
    }
}

struct SplashView: View {
    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 22) {
                Logo()
                HStack(spacing: 8) {
                    PulsingStripe()
                    Text("Connecting to BandBox…")
                        .font(.system(size: 13))
                        .foregroundStyle(Stage.secondaryText)
                }
            }
        }
    }
}

/// "BANDBOX" over "Stagehand" in Yellowtail, underlined with the four tone colors.
struct Logo: View {
    var size: CGFloat = 56

    static let bandboxAmber = Color(hex: 0xB07A1E)   // Stage.amber, dark enough for white
    static let toneColors = ToneSlot.all.map(\.color)

    var body: some View {
        VStack(spacing: 0) {
            Text("BANDBOX")
                .font(.system(size: size * 0.22, weight: .medium))
                .tracking(size * 0.22 * 0.32)
                .foregroundStyle(Self.bandboxAmber)
                .padding(.leading, size * 0.22 * 0.32)   // balance the tracking after the last letter
            Text("Stagehand")
                .font(.custom("Yellowtail-Regular", size: size))
                .foregroundStyle(Stage.background)
            HStack(spacing: size * 0.054) {
                ForEach(Self.toneColors.indices, id: \.self) { i in
                    Capsule().fill(Self.toneColors[i])
                }
            }
            .frame(width: size * 3.75, height: size * 0.072)
            .padding(.top, size * 0.11)
        }
    }
}

/// Four tone-colored dots lit one after another.
private struct PulsingStripe: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let lit = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 4
            HStack(spacing: 4) {
                ForEach(Logo.toneColors.indices, id: \.self) { i in
                    Circle()
                        .fill(Logo.toneColors[i])
                        .frame(width: 6, height: 6)
                        .opacity(i == lit ? 1 : 0.25)
                }
            }
        }
    }
}
