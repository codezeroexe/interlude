import CoreLocation
import EventKit
import ServiceManagement
import SwiftUI

/// One area of settings in the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, layout, widgets, wallpaper, music, notifications

    var id: Self { self }

    var name: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .layout: "Layout"
        case .widgets: "Widgets"
        case .wallpaper: "Wallpaper"
        case .music: "Music"
        case .notifications: "Notifications"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .layout: "rectangle.3.group"
        case .widgets: "square.grid.2x2"
        case .wallpaper: "photo.on.rectangle"
        case .music: "music.note"
        case .notifications: "bell.badge"
        }
    }
}

/// The settings window: a sidebar of areas and a grouped form for the chosen one, like System Settings.
/// Resizable, and reopens on the area used last.
struct SettingsView: View {
    static let windowID = "settings"
    let overlay: OverlayController
    @AppStorage("settingsPane") private var pane = SettingsPane.general

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: Binding { pane } set: { if let p = $0 { pane = p } }) { item in
                Label(item.name, systemImage: item.symbol).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
        } detail: {
            detail
                .navigationTitle(pane.name)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
        .onAppear { NSApp.activate() } // menu bar apps don't come forward on their own
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralSettings(overlay: overlay)
        case .appearance: AppearanceSettings(weather: overlay.model.weather)
        case .layout: LayoutSettings()
        case .widgets: WidgetSettings()
        case .wallpaper: WallpaperSettings()
        case .music: MusicSettings()
        case .notifications: NotificationSettings()
        }
    }
}

/// Minutes of no keyboard or mouse input before standby starts.
let idleChoices = [1, 2, 5, 10, 15, 30]

private struct GeneralSettings: View {
    let overlay: OverlayController
    @AppStorage(IdleMonitor.minutesKey) private var idleMinutes = IdleMonitor.defaultMinutes
    @StateObject private var login = LoginItem()
    @StateObject private var permissions = PermissionsModel()
    @AppStorage(StartConditions.onlyChargingKey) private var onlyCharging = false
    @AppStorage(StartConditions.skipWhenAwakeKey) private var skipWhenAwake = true
    @AppStorage(StartConditions.displayKey) private var display = ""

    var body: some View {
        Form {
            Section {
                Picker("Start Interlude after", selection: $idleMinutes) {
                    ForEach(idleChoices, id: \.self) { Text("\($0) min idle").tag($0) }
                }
                Toggle("Open at login", isOn: $login.enabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini) // single-row switch in a grouped form (HIG: toggles.md › Switches)
            } footer: {
                Text("Interlude keeps the display awake while it's showing. Press Esc or click the wallpaper to leave.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Only while charging", isOn: $onlyCharging)
                Toggle("Not while another app keeps the display on", isOn: $skipWhenAwake)
                Picker("Display", selection: $display) {
                    Text("Main Display").tag("")
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { Text($0).tag($0) }
                }
            } header: {
                Text("Starting on Its Own")
            } footer: {
                Text("Video calls, screen sharing, presentations and video players keep the display on, so Interlude waits until they finish. Starting Interlude from the menu ignores these rules.")
                    .foregroundStyle(.secondary)
            }
            Section {
                ForEach(permissions.items) { item in
                    LabeledContent {
                        if item.granted {
                            Label("Allowed", systemImage: "checkmark.circle.fill")
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(.secondary)
                        } else {
                            Button(item.canAsk ? "Allow…" : "Open Settings…") { permissions.fix(item.id) }
                        }
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                Text(item.purpose).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: item.symbol)
                        }
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Each one turns on one part of Interlude; everything else works without it. Restart Interlude after allowing Full Disk Access.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Show Interlude Now") { overlay.show() }
            } footer: {
                Text("Opens Interlude right away, to check a change. While it's open: Space plays or pauses, ← and → skip tracks, T starts the focus timer, Esc closes.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.reload() }
    }
}

/// What Interlude may access, for the Permissions list in General.
@MainActor
final class PermissionsModel: ObservableObject {
    enum Kind: String { case calendar, reminders, location, fullDisk }

    struct Item: Identifiable {
        let id: Kind
        let name: String
        let purpose: String
        let symbol: String
        let granted: Bool
        /// True when macOS can still show its own prompt; otherwise the fix is in System Settings.
        let canAsk: Bool
    }

    @Published private(set) var items: [Item] = []
    private let events = EKEventStore()
    private let location = CLLocationManager()

    func reload() {
        let cal = EKEventStore.authorizationStatus(for: .event)
        let rem = EKEventStore.authorizationStatus(for: .reminder)
        let loc = location.authorizationStatus
        items = [
            Item(id: .calendar, name: "Calendar", purpose: "Next event pill and hover details", symbol: "calendar",
                 granted: cal == .fullAccess, canAsk: cal == .notDetermined),
            Item(id: .reminders, name: "Reminders", purpose: "Reminders card", symbol: "checklist",
                 granted: rem == .fullAccess, canAsk: rem == .notDetermined),
            Item(id: .location, name: "Location", purpose: "Weather for where you are", symbol: "location",
                 granted: loc == .authorizedAlways || loc == .authorized, canAsk: loc == .notDetermined),
            Item(id: .fullDisk, name: "Full Disk Access", purpose: "Notification pills", symbol: "lock.shield",
                 granted: NotificationStore.hasAccess, canAsk: false),
        ]
    }

    func fix(_ kind: Kind) {
        guard let item = items.first(where: { $0.id == kind }) else { return }
        if item.canAsk {
            Task {
                switch kind {
                case .calendar: _ = try? await events.requestFullAccessToEvents()
                case .reminders: _ = try? await events.requestFullAccessToReminders()
                case .location: location.requestWhenInUseAuthorization()
                case .fullDisk: break
                }
                try? await Task.sleep(for: .seconds(1))
                reload()
            }
            return
        }
        let pane = switch kind {
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .location: "Privacy_LocationServices"
        case .fullDisk: "Privacy_AllFiles"
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}

/// Reads and writes the login item; SMAppService has no change notification, so it re-reads on set.
final class LoginItem: ObservableObject {
    var enabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            objectWillChange.send()
        }
    }
}

private struct AppearanceSettings: View {
    let weather: WeatherStore
    @AppStorage(ClockFont.key) private var clockFont = ClockFont.sfPro
    @AppStorage(GlassStyle.key) private var style = GlassStyle.frosted
    @AppStorage(GlassStyle.frostKey) private var frost = GlassStyle.defaultFrost
    @AppStorage(GlassStyle.transparencyKey) private var transparency = GlassStyle.defaultTransparency
    @AppStorage(GlassStyle.tintKey) private var tint = GlassStyle.defaultTint
    @AppStorage(GlassStyle.liquidToneKey) private var liquidTone = "dark"
    @AppStorage(ClockColor.key) private var clockColor = ClockColor.white
    @AppStorage(ClockColor.customKey) private var customColor = ""
    @AppStorage(NightMode.key) private var nightMode = NightMode.off
    @AppStorage(NightMode.startKey) private var nightStart = 22
    @AppStorage(NightMode.endKey) private var nightEnd = 7
    @AppStorage(NightMode.tintKey) private var nightTint = NightTint.red

    var body: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
            }
            Section("Clock") {
                Picker("Font", selection: $clockFont) {
                    ForEach(ClockFont.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Colour", selection: $clockColor) {
                    ForEach(ClockColor.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                if clockColor == .custom {
                    ColorPicker("Custom colour", selection: Binding {
                        ClockColor.custom(from: customColor)
                    } set: { customColor = ClockColor.raw(from: $0) }, supportsOpacity: false)
                }
            }
            Section {
                Picker("Night mode", selection: $nightMode) {
                    Text("Off").tag(NightMode.off)
                    Text("On a Schedule").tag(NightMode.scheduled)
                    Text("Always").tag(NightMode.always)
                }
                if nightMode == .scheduled {
                    Picker("From", selection: $nightStart) {
                        ForEach(0..<24, id: \.self) { Text(Self.hour($0)).tag($0) }
                    }
                    Picker("To", selection: $nightEnd) {
                        ForEach(0..<24, id: \.self) { Text(Self.hour($0)).tag($0) }
                    }
                }
                if nightMode != .off {
                    Picker("Colour", selection: $nightTint) {
                        Text("Red").tag(NightTint.red)
                        Text("Grey").tag(NightTint.grey)
                    }
                    .pickerStyle(.segmented)
                }
            } header: {
                Text("Night")
            } footer: {
                Text("At night Interlude hides the wallpaper and dims every card to one colour, easy on the eyes in a dark room. Red keeps your eyes adjusted to the dark.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Material", selection: $style) {
                    ForEach(GlassStyle.allCases, id: \.self) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                if style == .liquid {
                    Picker("Tint", selection: $liquidTone) {
                        Text("Dark").tag("dark")
                        Text("Light").tag("light")
                    }
                    .pickerStyle(.segmented)
                }
                if style == .frosted {
                    slider("Frost", value: $frost, low: "Clear", high: "Frosted")
                    slider("Transparency", value: $transparency, low: "Solid", high: "See-through")
                    slider("Tint", value: $tint, low: "None", high: "Dark")
                }
            } header: {
                Text("Cards")
            } footer: {
                Text(style == .frosted
                     ? "Frost sets how blurred the wallpaper behind each card is, Transparency how much of it shows through, and Tint how dark the cards are."
                     : "Liquid Glass matches the rest of your Mac; Tint picks its dark or light look. For clear or tinted glass, go to System Settings › Appearance.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .animation(.smooth(duration: 0.3), value: style)
        .animation(.smooth(duration: 0.3), value: nightMode)
        .animation(.smooth(duration: 0.3), value: clockColor)
    }

    private static func hour(_ h: Int) -> String {
        Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)!.formatted(date: .omitted, time: .shortened)
    }

    private func slider(_ title: String, value: Binding<Double>, low: String, high: String) -> some View {
        LabeledContent(title) {
            Slider(value: value, in: 0...1) {
                Text(title)
            } minimumValueLabel: {
                Text(low).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.caption).foregroundStyle(.secondary)
            }
            .labelsHidden()
        }
    }

    /// The real clock card over a colourful backdrop, so font, frost and transparency are easy to judge.
    private var preview: some View {
        let grid = Grid(size: CGSize(width: 900, height: 518))
        return ZStack {
            LinearGradient(colors: [.indigo, .blue, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.orange).frame(width: 150).offset(x: -120, y: -30)
            Circle().fill(.pink).frame(width: 110).offset(x: 140, y: 50)
            Text("10:41").font(.system(size: 120, weight: .black)).foregroundStyle(.white.opacity(0.35)).offset(x: 90, y: -40)
            ClockCard(weather: weather, grid: grid)
        }
        .frame(height: 210)
        .clipped()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .accessibilityLabel("Preview of the clock card")
    }
}

private struct WallpaperSettings: View {
    @AppStorage(AerialCatalog.selectionKey) private var wallpaper = AerialCatalog.defaultSelection

    var body: some View {
        Form {
            Section {
                Picker("Play", selection: $wallpaper) {
                    Section("Shuffle") {
                        Text("All aerials").tag("all")
                        ForEach(AerialCatalog.categories) { Text("All \($0.name)").tag("category:\($0.id)") }
                    }
                    ForEach(AerialCatalog.categories) { category in
                        Section(category.name) {
                            ForEach(category.aerials) { Text($0.name).tag("aerial:\($0.id)") }
                        }
                    }
                }
            } footer: {
                Text("These are the aerials from System Settings › Wallpaper. Ones you've downloaded there play from disk; the rest stream from Apple. Changes apply the next time Interlude starts.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct MusicSettings: View {
    @AppStorage(MusicLook.key) private var musicLook = MusicLook.album
    @AppStorage("monochromeArtwork") private var monochromeArtwork = true

    var body: some View {
        Form {
            Section {
                Picker("Background", selection: $musicLook) {
                    Text("Album colours").tag(MusicLook.album)
                    Text("Wallpaper").tag(MusicLook.wallpaper)
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text("While music plays")
            } footer: {
                Text("Album colours swaps the wallpaper for a slow backdrop made from the album art.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Monochrome album art", isOn: $monochromeArtwork)
            } footer: {
                Text("Shows the cover in the Now Playing card in grey and slightly see-through, to match the other cards.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct NotificationSettings: View {
    @StateObject private var model = NotificationSettingsModel()

    var body: some View {
        Form {
            Section {
                if model.hasAccess {
                    Label("Full Disk Access is on", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    LabeledContent("Full Disk Access is off") {
                        Button("Open Privacy & Security…") { NotificationStore.openFullDiskAccessSettings() }
                    }
                }
            } header: {
                Text("Access")
            } footer: {
                Text("Interlude reads Notification Center to show a pill per app. It needs Full Disk Access to do that; restart Interlude after turning it on.")
                    .foregroundStyle(.secondary)
            }
            Section {
                if model.hidden.isEmpty {
                    Text("No hidden apps").foregroundStyle(.secondary)
                } else {
                    ForEach(model.hidden, id: \.self) { bundleID in
                        LabeledContent(NotificationPill.name(for: bundleID)) {
                            Button("Show Again") { model.unhide(bundleID) }
                        }
                    }
                }
            } header: {
                Text("Hidden apps")
            } footer: {
                Text("Right-click a notification pill and choose Never Show to add an app here. Claude's notifications are always skipped; it has its own pill.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.reload() }
    }
}

final class NotificationSettingsModel: ObservableObject {
    @Published var hidden: [String] = []
    @Published var hasAccess = false

    func reload() {
        hidden = UserDefaults.standard.stringArray(forKey: NotificationStore.hiddenKey) ?? []
        hasAccess = NotificationStore.hasAccess
    }

    func unhide(_ bundleID: String) {
        hidden.removeAll { $0 == bundleID }
        UserDefaults.standard.set(hidden, forKey: NotificationStore.hiddenKey)
    }
}

/// Settings for individual widgets: World Clock cities and the focus timer's length.
private struct WidgetSettings: View {
    @AppStorage(WorldCity.key) private var raw = WorldCity.defaults
    @AppStorage(FocusTimer.minutesKey) private var minutes = 25
    private static let zones = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        let cities = WorldCity.load(raw)
        Form {
            Section {
                ForEach(cities.indices, id: \.self) { i in
                    HStack {
                        TextField("City \(i + 1)", text: Binding {
                            cities[i].name
                        } set: { edit(i) { $0.name = $1 }($0) })
                        .labelsHidden()
                        Picker("Time zone", selection: Binding {
                            cities[i].zone
                        } set: { edit(i) { $0.zone = $1 }($0) }) {
                            ForEach(Self.zones, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                Button("Reset to Default") { raw = WorldCity.defaults }
                    .disabled(raw == WorldCity.defaults)
            } header: {
                Text("World Clock")
            } footer: {
                Text("Four cities, each with its own name and time zone.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Length", selection: $minutes) {
                    ForEach([5, 10, 15, 20, 25, 30, 45, 50, 60, 90], id: \.self) { Text("\($0) min").tag($0) }
                }
            } header: {
                Text("Focus Timer")
            } footer: {
                Text("Click the timer on the Interlude screen to start or pause it; right-click it to reset. It keeps running while Interlude is closed and chimes when it ends.")
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("List", value: "Your default Reminders list")
            } header: {
                Text("Reminders")
            } footer: {
                Text("Shows the first four unfinished reminders. Click a circle on the Interlude screen to complete one. Change the default list in Reminders › Settings.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Returns a setter that changes one field of city `i` and saves the list.
    private func edit(_ i: Int, _ change: @escaping (inout WorldCity, String) -> Void) -> (String) -> Void {
        { value in
            var cities = WorldCity.load(raw)
            guard cities.indices.contains(i) else { return }
            change(&cities[i], value)
            raw = WorldCity.save(cities)
        }
    }
}
