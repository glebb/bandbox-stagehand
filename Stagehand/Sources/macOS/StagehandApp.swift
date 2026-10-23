import IOKit.pwr_mgt
import SwiftUI

@main
struct StagehandApp: App {
    @StateObject private var client = BandBoxClient()
    @StateObject private var assignments = ToneAssignments()
    private let keepAwake = KeepAwake()
    @StateObject private var hotKeys = GlobalHotKeys()
    @StateObject private var midi = MIDIInput()
    @StateObject private var songTones = ScratchFiller()

    var body: some Scene {
        WindowGroup("Bandbox Stagehand") {
            RootView()
                .environmentObject(client)
                .environmentObject(assignments)
                .environmentObject(hotKeys)
                .environmentObject(midi)
                .environmentObject(songTones)
                .preferredColorScheme(.dark)
                .onAppear {
                    hotKeys.start(client: client, assignments: assignments)
                    midi.start(client: client, assignments: assignments, filler: songTones)
                }
        }
        .windowResizability(.contentMinSize)
    }
}
