import SwiftUI
#if os(iOS)
import UIKit
#endif

/// "Stage black": a near-black stage with quiet tiles. Colour appears only where it means
/// something: the selected tone, and amber for anything that's switched on.
enum Stage {
    static let background = Color(hex: 0x0C0C0D)
    static let tile = Color(hex: 0x141416)
    static let tileBorder = Color(hex: 0x222226)
    static let toneTile = Color(hex: 0x131315)
    static let toneBorder = Color(hex: 0x1F1F22)
    static let text = Color(hex: 0xF4F1EA)
    static let secondaryText = Color(hex: 0x8A8A92)
    static let mutedText = Color(hex: 0x6E6E75)
    static let faintText = Color(hex: 0x55555C)
    static let control = Color(hex: 0xB9B9C0)        // + and − glyphs
    static let amber = Color(hex: 0xF5C46A)          // "on"
    static let amberTint = Color(hex: 0x1F1A11)
    static let amberBorder = Color(hex: 0x5A4520)
    static let meterTrack = Color(hex: 0x26262A)
    static let tick = Color(hex: 0x4A4A50)
    static let inTune = Color(hex: 0x7FD3A8)
    static let tunerBorder = Color(hex: 0x2F5A44)
    static let segmentSelected = Color(hex: 0x2A2A2F)
    static let stemType = Color(hex: 0xC9C4F5)
    static let dot = Color(hex: 0x2E2E33)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// A big touch target. Fires on release without movement, so a swipe that starts on it changes page instead.
/// With `longPress`, holding it for half a second runs that instead of `action`.
/// (No pressed highlight: tracking the press with a gesture state stops clicks from registering on macOS.)
struct Pad<Label: View>: View {
    var fill: Color = Stage.tile
    var border: Color = Stage.tileBorder
    var borderWidth: CGFloat = 1
    var longPress: (() -> Void)?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        shape
            .fill(fill)
            .overlay(shape.strokeBorder(border, lineWidth: borderWidth))
            .overlay(label().padding(.horizontal, 8).padding(.vertical, 12))
            .clipShape(shape)
            .contentShape(shape)
            .animation(.easeOut(duration: 0.2), value: fill)
            .gesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in Haptics.tap(); (longPress ?? action)() }
                    .exclusively(before: TapGesture().onEnded { Haptics.tap(); action() }))
    }
}

/// A short tick on the iPhone for every press, so a tap is felt before the speaker confirms it.
enum Haptics {
    #if os(iOS)
    private static let generator = UIImpactFeedbackGenerator(style: .light)
    #endif

    static func tap() {
        #if os(iOS)
        generator.impactOccurred()
        #endif
    }
}

/// A pedal-style switch: quiet when off; amber label, warm tint and a short glowing line when on.
struct SwitchPad<Label: View>: View {
    let on: Bool
    var longPress: (() -> Void)?
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Pad(fill: on ? Stage.amberTint : Stage.tile,
            border: on ? Stage.amberBorder : Stage.tileBorder,
            longPress: longPress,
            action: action) {
            label().foregroundStyle(on ? Stage.amber : Stage.mutedText)
        }
        .overlay(alignment: .bottom) {
            if on {
                Capsule().fill(Stage.amber).frame(width: 20, height: 2).padding(.bottom, 7)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Header, +, level (big percent over a slim meter), −. Steps one knob click per tap.
struct VolumeColumn<Header: View>: View {
    let level: Int?
    let change: (Int) -> Void
    @ViewBuilder var header: () -> Header

    var body: some View {
        GeometryReader { geo in
            // header, then + / level / − sharing the rest 1 : 1.25 : 1. Without a header the
            // column is that much shorter, so it lines up with a headed one beside a header row.
            let hasHeader = Header.self != EmptyView.self
            let headerHeight: CGFloat = hasHeader ? 26 : 0, spacing: CGFloat = 8
            let unit = max(geo.size.height - headerHeight - spacing * (hasHeader ? 3 : 2), 0) / 3.25
            VStack(spacing: spacing) {
                if hasHeader {
                    header()
                        .frame(height: headerHeight)
                }
                Pad(action: { change(1) }) {
                    Image(systemName: "plus").font(.system(size: 20, weight: .light)).foregroundStyle(Stage.control)
                }
                .frame(height: unit)
                LevelTile(level: level)
                    .frame(height: unit * 1.25)
                Pad(action: { change(-1) }) {
                    Image(systemName: "minus").font(.system(size: 20, weight: .light)).foregroundStyle(Stage.control)
                }
                .frame(height: unit)
            }
        }
    }
}

extension VolumeColumn where Header == EmptyView {
    init(level: Int?, change: @escaping (Int) -> Void) {
        self.init(level: level, change: change) { EmptyView() }
    }
}

extension VolumeColumn where Header == ColumnTitle {
    init(title: String, level: Int?, change: @escaping (Int) -> Void) {
        self.init(level: level, change: change) { ColumnTitle(text: title) }
    }
}

struct ColumnTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Stage.secondaryText)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LevelTile: View {
    let level: Int?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let fraction = CGFloat(level ?? 0) / CGFloat(BandBoxClient.levelRange.upperBound)
        shape
            .fill(Stage.tile)
            .overlay(shape.strokeBorder(Stage.tileBorder, lineWidth: 1))
            .overlay {
                VStack(spacing: 9) {
                    Text(level.map { "\(BandBoxClient.percent($0))%" } ?? "–")
                        .font(.system(size: 22, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(level == nil ? Stage.faintText : Stage.text)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Stage.meterTrack)
                            Capsule().fill(Stage.text).frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 22)
                }
                .padding(.vertical, 12)
                .animation(.easeOut(duration: 0.15), value: level)
            }
    }
}

/// A row of options with the chosen one lifted, e.g. channel 1–4.
struct Segmented: View {
    let options: [Int]
    let selected: Int
    var label: (Int) -> String = { "\($0)" }
    var enabled: (Int) -> Bool = { _ in true }
    let pick: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { n in
                Text(label(n))
                    .font(.system(size: 12, weight: n == selected ? .medium : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(n == selected ? Stage.text : Stage.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(n == selected ? Stage.segmentSelected : .clear))
                    .opacity(enabled(n) ? 1 : 0.35)
                    .contentShape(Rectangle())
                    .onTapGesture { if enabled(n) { pick(n) } }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Stage.tile))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Stage.tileBorder, lineWidth: 1))
    }
}

/// The four tone buttons and which speaker tone each one selects (long-press to change).
struct ToneSlot: Identifiable {
    let id: Int
    let name: String
    let color: Color     // tab, outline and name when selected
    let tint: Color      // fill when selected
    let defaultTone: Int

    static let all = [
        ToneSlot(id: 0, name: "Clean", color: Color(hex: 0x5DCAA5), tint: Color(hex: 0x13241E), defaultTone: 0x01),
        ToneSlot(id: 1, name: "Crunch", color: Color(hex: 0xEF9F27), tint: Color(hex: 0x2A1E0D), defaultTone: 0x0F),
        ToneSlot(id: 2, name: "Heavy", color: Color(hex: 0xE8615F), tint: Color(hex: 0x2B1414), defaultTone: 0x16),
        ToneSlot(id: 3, name: "Lead", color: Color(hex: 0x9D96F0), tint: Color(hex: 0x1C1A33), defaultTone: 0x11),
    ]
}

/// Each guitar channel's button tones and the names the user gave them ("" = the slot's own name).
/// Channel 3 keeps the settings saved before there were channels; channel 1 starts as a copy.
final class ToneAssignments: ObservableObject {
    @Published private var tones: [Int: [Int]] {
        didSet { for (channel, t) in tones { UserDefaults.standard.set(t, forKey: Self.key("toneSlots", channel)) } }
    }

    @Published private var names: [Int: [String]] {
        didSet { for (channel, n) in names { UserDefaults.standard.set(n, forKey: Self.key("toneSlotNames", channel)) } }
    }

    private static func key(_ base: String, _ channel: Int) -> String {
        channel == 3 ? base : "\(base).ch\(channel)"
    }

    init() {
        let count = ToneSlot.all.count
        func savedTones(_ channel: Int) -> [Int]? {
            (UserDefaults.standard.array(forKey: Self.key("toneSlots", channel)) as? [Int]).flatMap { $0.count == count ? $0 : nil }
        }
        func savedNames(_ channel: Int) -> [String]? {
            UserDefaults.standard.stringArray(forKey: Self.key("toneSlotNames", channel)).flatMap { $0.count == count ? $0 : nil }
        }
        let tones3 = savedTones(3) ?? ToneSlot.all.map(\.defaultTone)
        let names3 = savedNames(3) ?? Array(repeating: "", count: count)
        tones = [3: tones3, 1: savedTones(1) ?? tones3]
        names = [3: names3, 1: savedNames(1) ?? names3]
    }

    func tone(_ slot: ToneSlot, channel: Int) -> Int { tones[channel]?[slot.id] ?? slot.defaultTone }

    func assign(_ tone: Int, to slot: Int, channel: Int) { tones[channel]?[slot] = tone }

    func name(_ slot: ToneSlot, channel: Int) -> String {
        let custom = (names[channel]?[slot.id] ?? "").trimmingCharacters(in: .whitespaces)
        return custom.isEmpty ? slot.name : custom
    }

    /// The custom name as typed, for the rename field.
    func customName(_ slot: ToneSlot, channel: Int) -> Binding<String> {
        Binding(get: { self.names[channel]?[slot.id] ?? "" },
                set: { self.names[channel]?[slot.id] = $0 })
    }
}
