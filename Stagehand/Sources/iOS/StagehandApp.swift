import SwiftUI
import UIKit

@main
struct StagehandApp: App {
    @StateObject private var client = BandBoxClient()
    @StateObject private var assignments = ToneAssignments()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(client)
                .environmentObject(assignments)
                .preferredColorScheme(.dark)
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                // Keep the screen on while the app is open, so the controls stay visible while playing.
                .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
                .onChange(of: scenePhase) { _, phase in
                    UIApplication.shared.isIdleTimerDisabled = phase == .active
                }
        }
    }
}
