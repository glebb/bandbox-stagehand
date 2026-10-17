import IOKit.pwr_mgt
import SwiftUI

@main
struct StagehandApp: App {
    @StateObject private var client = BandBoxClient()
    @StateObject private var assignments = ToneAssignments()
    private let keepAwake = KeepAwake()

    var body: some Scene {
        WindowGroup("Bandbox Stagehand") {
            RootView()
                .environmentObject(client)
                .environmentObject(assignments)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentMinSize)
    }
}

/// Turns a two-finger horizontal trackpad swipe into one page step (fingers left = next page).
final class TrackpadSwipe {
    private var monitor: Any?
    private var distance: CGFloat = 0
    private var fired = false

    func start(_ turn: @escaping (Int) -> Void) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.momentumPhase.isEmpty else { return event }
            if event.phase.contains(.began) {
                distance = 0
                fired = false
            }
            guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || distance != 0 else { return event }
            // Finger direction, whatever the natural-scrolling setting.
            distance += event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            if !fired, abs(distance) > 50 {
                fired = true
                turn(distance < 0 ? 1 : -1)
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}

/// Keeps the display awake while the app runs, so the controls stay visible while playing.
final class KeepAwake {
    private var assertion: IOPMAssertionID = 0

    init() {
        IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                                    IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                    "Stagehand is open" as CFString, &assertion)
    }

    deinit { IOPMAssertionRelease(assertion) }
}
