import AppKit
import CoreGraphics

/// Opens the overlay once the Mac has had no keyboard, mouse or trackpad input for a while.
@MainActor
final class IdleMonitor {
    static let minutesKey = "idleMinutes"
    static let defaultMinutes = 5

    private let overlay: OverlayController
    private var timer: Timer?
    /// While auto-start is blocked, the scan below waits this long between runs.
    private var blockedUntil = Date.distantPast

    init(overlay: OverlayController) {
        self.overlay = overlay
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = 1
    }

    private func tick() {
        guard !overlay.isShowing else { return } // the assertion scan below is not free
        // Any input type (kCGAnyInputEventType). Needs no permissions.
        let anyInput = CGEventType(rawValue: ~0)!
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
        let stored = UserDefaults.standard.integer(forKey: Self.minutesKey)
        let minutes = stored > 0 ? stored : Self.defaultMinutes
        guard idle >= Double(minutes * 60) else { blockedUntil = .distantPast; return } // input resets the backoff
        guard Date() >= blockedUntil else { return }
        if StartConditions.allowAutoStart(pluggedIn: BatteryMonitor.isPluggedIn) {
            overlay.show() // refreshes the battery card data itself
        } else {
            blockedUntil = Date().addingTimeInterval(10)
        }
    }
}
