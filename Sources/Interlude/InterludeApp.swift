import SwiftUI

@main
struct InterludeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Interlude", systemImage: "clock") {
            MenuContent(overlay: delegate.overlay)
        }
        // A full, resizable window with a sidebar, like System Settings, instead of a small fixed panel.
        Window("Interlude Settings", id: SettingsView.windowID) {
            SettingsView(overlay: delegate.overlay)
        }
        .defaultSize(width: 920, height: 700)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appSettings) { OpenSettingsButton() }
        }
    }
}

/// "Settings…" with ⌘, — opens the settings window and brings it forward.
struct OpenSettingsButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Settings…") {
            openWindow(id: SettingsView.windowID)
            NSApp.activate()
        }
        .keyboardShortcut(",")
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let overlay = OverlayController()
    private var idle: IdleMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ClockFont.registerBundledFonts()
        // Ask for calendar, location and player-control access now, while no overlay covers the system prompt.
        overlay.model.calendar.requestAccess()
        overlay.model.weather.requestAccess()
        overlay.model.reminders.requestAccess()
        overlay.model.nowPlaying.requestPermissions()
        idle = IdleMonitor(overlay: overlay)
        idle?.start()
        // `open Interlude.app --args --show` opens the overlay straight away (handy for testing).
        if CommandLine.arguments.contains("--show") { overlay.show() }
        // `Interlude --render-cards <folder>` saves each card as a PNG and quits (for checking layouts).
        if let i = CommandLine.arguments.firstIndex(of: "--render-cards"), i + 1 < CommandLine.arguments.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                CardRenderer.render(model: self.overlay.model, to: URL(fileURLWithPath: CommandLine.arguments[i + 1]))
                NSApp.terminate(nil)
            }
        }
    }
}

/// The menu bar menu: Start Now, the idle timer, Settings and Quit. Everything else lives in Settings.
struct MenuContent: View {
    let overlay: OverlayController
    @AppStorage(IdleMonitor.minutesKey) private var idleMinutes = IdleMonitor.defaultMinutes

    var body: some View {
        Button("Start Interlude Now") { overlay.show() }
            .keyboardShortcut("s")
        Divider()
        Picker("Start Interlude After", selection: $idleMinutes) {
            ForEach(idleChoices, id: \.self) { Text("\($0) min idle").tag($0) }
        }
        Divider()
        OpenSettingsButton()
        Button("Quit Interlude") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
