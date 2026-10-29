import AppKit
import CoreGraphics

/// Opens the overlay once the Mac has had no keyboard, mouse or trackpad input for a while.
@MainActor
final class IdleMonitor {
    static let minutesKey = "idleMinutes"
    static let defaultMinutes = 5

    private let overlay: OverlayController
    private var timer: Timer?

    init(overlay: OverlayController) {
        self.overlay = overlay
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        // Any input type (kCGAnyInputEventType). Needs no permissions.
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let stored = UserDefaults.standard.integer(forKey: Self.minutesKey)
        let minutes = stored > 0 ? stored : Self.defaultMinutes
        if idle >= Double(minutes * 60), StartConditions.allowAutoStart(pluggedIn: overlay.model.battery.pluggedIn) {
            overlay.show()
        }
    }
}
