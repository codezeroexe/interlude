import AppKit
import IOKit.pwr_mgt
import SwiftUI

/// Data the overlay shows. Lives for the whole app run so state survives show and hide.
@MainActor
final class OverlayModel {
    let battery = BatteryMonitor()
    let calendar = CalendarStore()
    let aerial = AerialPlayer()
    let weather = WeatherStore()
    let nowPlaying: NowPlaying
    let reminders = ReminderStore()
    let timer = FocusTimer()
    let night = NightMonitor()
    let entrance = Entrance()

    init(nowPlaying: NowPlaying? = nil) { self.nowPlaying = nowPlaying ?? NowPlaying() }
}

/// Owns the full-screen window: shows it on idle, hides it on Esc or a click on the wallpaper.
@MainActor
final class OverlayController {
    let model = OverlayModel()

    /// Sample data for the welcome window's previews, which show before any access is granted.
    /// Shares the real Now Playing, so the song playing now shows; the sample song otherwise.
    lazy var demo: OverlayModel = {
        let demo = OverlayModel(nowPlaying: model.nowPlaying)
        demo.battery.preview()
        demo.calendar.preview()
        demo.weather.preview()
        demo.reminders.preview()
        return demo
    }()

    private var window: OverlayWindow?
    private var keyMonitor: Any?
    private var sleepAssertion: IOPMAssertionID = 0
    /// The 650 ms exit animation's cleanup, and the window it will close.
    private var pendingHide: (task: Task<Void, Never>, window: OverlayWindow)?

    var isShowing: Bool { window != nil }

    func show() {
        guard window == nil, let screen = StartConditions.screen else { return }
        // Shown again mid-exit: drop the cleanup. The old window closes now, and the monitors it
        // would have stopped keep running, so they are not started a second time below.
        let resuming = pendingHide != nil
        if let pending = pendingHide {
            pending.task.cancel()
            pending.window.orderOut(nil)
            pendingHide = nil
        }

        let w = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Transparent, so the desktop shows through while the wallpaper fades and settles in.
        w.backgroundColor = .clear
        w.isOpaque = false
        w.hasShadow = false
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: OverlayView(model: model) { [weak self] in self?.hide() })
        w.setFrame(screen.frame, display: true)
        window = w

        model.entrance.shown = false
        model.battery.refresh()
        model.calendar.refresh()
        model.weather.refresh()
        model.reminders.refresh()
        if !resuming {
            model.battery.start()
            model.night.start()
            model.nowPlaying.start()
        }
        model.night.check()
        model.aerial.play()

        // A non-activating panel takes key focus without waiting for macOS to let the app come forward,
        // so Esc and clicks work at once even when standby starts on its own while another app is active.
        w.makeKeyAndOrderFront(nil)
        NSApp.activate()
        NSCursor.setHiddenUntilMouseMoves(true)
        // Let the first frame draw in the hidden state, then animate everything in.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.model.entrance.shown = true }

        // Esc closes. Space plays or pauses, ← and → skip tracks, T starts or pauses the focus timer.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 53: self.hide()
            case 49: self.model.nowPlaying.send(.playPause)
            case 123: self.model.nowPlaying.send(.previous)
            case 124: self.model.nowPlaying.send(.next)
            default:
                guard event.charactersIgnoringModifiers?.lowercased() == "t" else { return event }
                self.model.timer.toggle()
            }
            return nil
        }
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Interlude overlay is showing" as CFString,
            &sleepAssertion
        )
    }

    func hide() {
        guard let w = window else { return }
        window = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if sleepAssertion != 0 { IOPMAssertionRelease(sleepAssertion) }
        sleepAssertion = 0
        // Exit animation: cards drop away, then the wallpaper fades out to the desktop.
        model.entrance.shown = false
        let task = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            pendingHide = nil
            w.orderOut(nil)
            model.aerial.unload()
            model.battery.stop()
            model.night.stop()
            model.nowPlaying.stop()
            model.nowPlaying.requestPermissions()
        }
        pendingHide = (task, w)
    }
}

/// Borderless windows refuse key focus by default; the overlay needs it so Esc works.
final class OverlayWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
