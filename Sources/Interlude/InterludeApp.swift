import SwiftUI

@main
struct InterludeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The welcome window can draw before the app finishes launching, so the clock fonts load first.
    init() { ClockFont.registerBundledFonts() }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(overlay: delegate.overlay)
        } label: {
            Image(nsImage: MenuBarIcon.image)
        }
        // A full, resizable window with a sidebar, like System Settings, instead of a small fixed panel.
        Window("Interlude Settings", id: SettingsView.windowID) {
            SettingsView(overlay: delegate.overlay)
                .windowMinimizeBehavior(.disabled) // ⌘, reopens it, so it needn't sit in the Dock
        }
        .defaultSize(width: 860, height: 620)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) { OpenSettingsButton() }
        }
        // Opens by itself on the first launch only; Settings › Privacy can show it again.
        Window("Welcome to Interlude", id: OnboardingView.windowID) {
            OnboardingView(overlay: delegate.overlay)
                .windowMinimizeBehavior(.disabled)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: OnboardingView.doneKey) ? .suppressed : .presented)
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
        // After the welcome window has run, ask for anything still undecided now, while no overlay covers
        // the system prompt. Before that, the welcome window asks, one card at a time.
        if UserDefaults.standard.bool(forKey: OnboardingView.doneKey) {
            overlay.model.calendar.requestAccess()
            overlay.model.weather.requestAccess()
            overlay.model.reminders.requestAccess()
            overlay.model.nowPlaying.requestPermissions()
        }
        idle = IdleMonitor(overlay: overlay)
        idle?.start()
        // `open Interlude.app --args --show` opens the overlay straight away (handy for testing).
        if CommandLine.arguments.contains("--show") { overlay.show() }
        // `Interlude --render-settings <folder>` saves each Settings pane as a PNG and quits.
        if let i = CommandLine.arguments.firstIndex(of: "--render-settings"), i + 1 < CommandLine.arguments.count {
            let pane = UserDefaults.standard.string(forKey: "settingsPane")
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                CardRenderer.renderSettings(overlay: self.overlay, to: URL(fileURLWithPath: CommandLine.arguments[i + 1])) {
                    UserDefaults.standard.set(pane, forKey: "settingsPane")
                    NSApp.terminate(nil)
                }
            }
        }
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
