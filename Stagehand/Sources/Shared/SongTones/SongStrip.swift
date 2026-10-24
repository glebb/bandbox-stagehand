import SwiftUI

/// Above a tones page, while a song's tones play on its channel: the song, its tones (tap one to
/// play it), the one playing lit in its slot's colour, and how the fill went.
struct SongStrip: View {
    @ObservedObject var song: ScratchFiller
    /// The song tone the channel plays. Passed in rather than read from `song`: it follows the
    /// client's presets, which the strip doesn't watch, so read here it lagged one change behind.
    let playing: Int?
    @EnvironmentObject private var assignments: ToneAssignments

    var body: some View {
        HStack(spacing: 8) {
            if let request = song.request {
                Text("♪ " + [request.song, request.artist].filter { !$0.isEmpty }.joined(separator: " · "))
                    .foregroundStyle(Stage.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(-1)
                ForEach(request.tones.indices, id: \.self) { i in
                    let slot = ToneSlot.all[request.tones[i].slot]
                    let playing = self.playing == i
                    Text("\(i + 1) \(slot.name)")
                        .font(.system(size: 11, weight: playing ? .semibold : .regular))
                        .foregroundStyle(playing ? slot.color : song.ready.contains(i) ? Stage.secondaryText : Stage.faintText)
                        .padding(.horizontal, 8)
                        .frame(height: 20)
                        .background(Capsule().fill(playing ? slot.tint : Stage.tile))
                        .overlay(Capsule().strokeBorder(playing ? slot.color : Stage.tileBorder, lineWidth: 1))
                        .fixedSize()
                        .contentShape(Capsule())
                        .onTapGesture { song.play(i) }
                        .help(request.tones[i].key)
                }
                Spacer(minLength: 8)
                switch song.state {
                case let .filling(done, of):
                    Text("Building song tones \(done)/\(of)…").foregroundStyle(Stage.amber)
                case let .failed(reason):
                    Text("Song tones failed: \(reason)").foregroundStyle(Color(hex: 0xE8615F)).lineLimit(1)
                default:
                    Text(request.bank.isEmpty ? assignments.bankName : request.bank).foregroundStyle(Stage.faintText)
                }
            }
        }
        .font(.system(size: 12))
        .frame(height: 22)
    }
}
