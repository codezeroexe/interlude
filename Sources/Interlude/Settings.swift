import CoreLocation
import EventKit
import ServiceManagement
import SwiftUI

/// One area of settings in the sidebar.
enum SettingsPane: String, CaseIterable, Identifiable {
    case general, appearance, layout, widgets, wallpaper, music, privacy

    var id: Self { self }

    var name: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .layout: "Layout"
        case .widgets: "Widgets"
        case .wallpaper: "Wallpaper"
        case .music: "Music"
        case .privacy: "Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .appearance: "circle.lefthalf.filled"
        case .layout: "square.grid.3x3.square"
        case .widgets: "square.grid.2x2"
        case .wallpaper: "photo"
        case .music: "music.note"
        case .privacy: "hand.raised.fill"
        }
    }

    /// The sidebar heading this area sits under.
    var group: String {
        switch self {
        case .general, .appearance: "Interlude"
        case .layout, .widgets, .wallpaper: "Screen"
        case .music, .privacy: "Features"
        }
    }

    /// Words the sidebar search also matches, beyond the name.
    var keywords: String {
        switch self {
        case .general: "idle start login charging display shortcuts"
        case .appearance: "clock font serif colour color night red glass frosted liquid tint transparency frost"
        case .layout: "grid size rows widgets move resize style add remove music night profile"
        case .widgets: "world clock cities time zone focus timer length reminders list"
        case .wallpaper: "aerial video shuffle background"
        case .music: "album colours backdrop monochrome artwork now playing"
        case .privacy: "permissions access calendar reminders location music spotify welcome tour"
        }
    }

    static let groups = ["Interlude", "Screen", "Features"]

    func matches(_ query: String) -> Bool {
        query.isEmpty || "\(name) \(keywords)".localizedCaseInsensitiveContains(query)
    }
}

/// The sidebar's search text and the back/forward history. (A model object: no SwiftUI macros here.)
final class SettingsNavigation: ObservableObject {
    @Published var search = ""
    private(set) var back: [SettingsPane] = []
    private(set) var forward: [SettingsPane] = []

    /// Records leaving `from` for another area, as a browser does.
    func visit(from: SettingsPane) {
        back.append(from)
        forward.removeAll()
        objectWillChange.send()
    }

    func goBack(from current: SettingsPane) -> SettingsPane? {
        guard let pane = back.popLast() else { return nil }
        forward.append(current)
        objectWillChange.send()
        return pane
    }

    func goForward(from current: SettingsPane) -> SettingsPane? {
        guard let pane = forward.popLast() else { return nil }
        back.append(current)
        objectWillChange.send()
        return pane
    }
}

/// A symbol in a small graphite tile, as in the mockup's sidebar and permission rows.
struct PaneIcon: View {
    let symbol: String
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.36, blue: 0.38), Color(red: 0.17, green: 0.17, blue: 0.19)],
                                     startPoint: .top, endPoint: .bottom)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.27, style: .continuous).strokeBorder(.white.opacity(0.2), lineWidth: 0.5))
    }
}

/// The settings window, as in reference/settings-onboarding.html: a searchable sidebar of areas under
/// headings, back and forward buttons with the area's name, and grouped rows. Reopens on the area used last.
struct SettingsView: View {
    static let windowID = "settings"
    let overlay: OverlayController
    @AppStorage("settingsPane") private var pane = SettingsPane.general
    @StateObject private var nav = SettingsNavigation()

    var body: some View {
        // As in the mockup: a see-through window, a floating sidebar panel with the window buttons in its
        // top corner, and the back and forward capsule level with them beside the area's name.
        HStack(spacing: 0) {
            sidebar
                .frame(width: 236)
                .frame(maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.primary.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
                .padding(8)
            VStack(spacing: 0) {
                toolbar
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // The scroll edge: rows fade out under the toolbar row instead of meeting a hard line.
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.025)],
                                         startPoint: .top, endPoint: .bottom))
            }
        }
        .navigationTitle(pane.name) // the window's title, for the Window menu and Mission Control
        .background(SeeThroughWindow())
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .ignoresSafeArea()
        .frame(minWidth: 760, minHeight: 560)
        .tint(.graphite)
        .onAppear { NSApp.activate() } // menu bar apps don't come forward on their own
        // Previews show the song playing now, so keep reading the player while Settings is open.
        .onAppear { overlay.model.nowPlaying.start() }
        .onDisappear { overlay.model.nowPlaying.stop() }
    }

    /// Back and forward in one capsule, then the area's name, centred on the window buttons' line.
    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                Button { if let p = nav.goBack(from: pane) { pane = p } } label: {
                    Image(systemName: "chevron.left").frame(width: 30, height: 28).contentShape(Rectangle())
                }
                .disabled(nav.back.isEmpty)
                .keyboardShortcut("[")
                .accessibilityLabel("Back")
                Button { if let p = nav.goForward(from: pane) { pane = p } } label: {
                    Image(systemName: "chevron.right").frame(width: 30, height: 28).contentShape(Rectangle())
                }
                .disabled(nav.forward.isEmpty)
                .keyboardShortcut("]")
                .accessibilityLabel("Forward")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .background(Capsule().fill(Color.groupFill))
            .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            Text(pane.name).font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.leading, 4)
        .padding(.trailing, 20)
        .frame(height: 52)
    }

    /// Plain rows with a soft grey highlight, instead of the accent-coloured list selection.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window's close, minimise and zoom buttons sit here, centred 26 points from the top.
            Color.clear.frame(height: 44)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $nav.search).textFieldStyle(.plain)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            sidebarList
        }
    }

    private var sidebarList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(SettingsPane.groups, id: \.self) { group in
                    let panes = SettingsPane.allCases.filter { $0.group == group && $0.matches(nav.search) }
                    if !panes.isEmpty {
                        Text(group)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(panes) { item in
                            Button { go(to: item) } label: {
                                HStack(spacing: 9) {
                                    PaneIcon(symbol: item.symbol)
                                    Text(item.name).fontWeight(item == pane ? .medium : .regular)
                                    Spacer()
                                }
                                .font(.system(size: 13))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(item == pane ? Color.primary.opacity(0.09) : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(item == pane ? .isSelected : [])
                        }
                    }
                }
                if SettingsPane.allCases.allSatisfy({ !$0.matches(nav.search) }) {
                    Text("No Results")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private func go(to new: SettingsPane) {
        guard new != pane else { return }
        nav.visit(from: pane)
        pane = new
    }

    @ViewBuilder private var detail: some View {
        switch pane {
        case .general: GeneralSettings(overlay: overlay)
        case .appearance: AppearanceSettings(model: overlay.model)
        case .layout: LayoutSettings(model: overlay.model)
        case .widgets: WidgetSettings(model: overlay.model)
        case .wallpaper: WallpaperSettings()
        case .music: MusicSettings(model: overlay.model)
        case .privacy: PrivacySettings(overlay: overlay)
        }
    }
}

/// Minutes of no keyboard or mouse input before standby starts.
let idleChoices = [1, 2, 5, 10, 15, 30]

private struct GeneralSettings: View {
    let overlay: OverlayController
    @AppStorage(IdleMonitor.minutesKey) private var idleMinutes = IdleMonitor.defaultMinutes
    @StateObject private var login = LoginItem()
    @AppStorage(StartConditions.onlyChargingKey) private var onlyCharging = false
    @AppStorage(StartConditions.skipWhenAwakeKey) private var skipWhenAwake = true
    @AppStorage(StartConditions.displayKey) private var display = ""

    var body: some View {
        SettingsPage {
            SettingsGroup(footer: "While it's open: Space plays or pauses, ← and → skip tracks, T starts the focus timer, Esc closes.") {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Interlude").font(.system(size: 17, weight: .semibold))
                        Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Show Now") { overlay.show() }
                        .buttonStyle(.capsule)
                }
                .padding(14)
            }
            SettingsGroup(title: "Starting") {
                SettingsRow(title: "Start Interlude after", subtitle: "How long your Mac sits idle first") {
                    PopupMenu(selection: $idleMinutes, choices: idleChoices.map { Choice($0 == 1 ? "1 minute" : "\($0) minutes", $0) })
                }
                SettingsRow(title: "Open at login", subtitle: "Starts quietly in the menu bar") {
                    Toggle("Open at login", isOn: $login.enabled).labelsHidden()
                }
            }
            SettingsGroup(title: "When to Stay Away", footer: "Starting Interlude from the menu bar ignores these.") {
                SettingsRow(title: "Only while charging", subtitle: "Saves battery on the go") {
                    Toggle("Only while charging", isOn: $onlyCharging).labelsHidden()
                }
                SettingsRow(title: "Not while another app keeps the display on", subtitle: "For example during a video call or a film") {
                    Toggle("Not while another app keeps the display on", isOn: $skipWhenAwake).labelsHidden()
                }
                SettingsRow(title: "Display", subtitle: "Where Interlude appears") {
                    PopupMenu(selection: $display, choices: [Choice("Main Display", "")] + NSScreen.screens.map { Choice($0.localizedName, $0.localizedName) })
                }
            }
        }
    }
}

private struct AppearanceSettings: View {
    let model: OverlayModel
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
        SettingsPage {
            // The real cards over the wallpaper, so font and glass are easy to judge.
            // With "Match Music" the music card joins the preview, so the clock's colour has its source.
            StandbyScene(model: model, cards: clockColor == .music
                         ? [[(.nowPlaying, .medium, 0)], [(.weather, .small, 0), (.calendar, .small, 1)]]
                         : [[(.weather, .medium, 0)], [(.calendar, .medium, 0)]])
                .environment(\.previewMusic, true)
                .frame(height: 196)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 6)
            SettingsGroup(title: "Clock") {
                SettingsRow(title: "Font") {
                    Segmented(selection: $clockFont, choices: [Choice("SF Pro", .sfPro), Choice("Serif", .instrumentSerif)])
                }
                SettingsRow(title: "Colour") {
                    PopupMenu(selection: $clockColor, choices: ClockColor.allCases.map { Choice($0.name, $0) })
                }
                if clockColor == .custom {
                    SettingsRow(title: "Custom colour") {
                        ColorPicker("Custom colour", selection: Binding {
                            ClockColor.custom(from: customColor)
                        } set: { customColor = ClockColor.raw(from: $0) }, supportsOpacity: false)
                        .labelsHidden()
                    }
                }
            }
            SettingsGroup(title: "Night") {
                if nightMode != .off {
                    // How the screen looks at night, in the colour picked below.
                    StandbyScene(model: model, cards: [[(.weather, .medium, 0)], [(.calendar, .medium, 0)]], night: nightTint)
                        .frame(height: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(10)
                        .animation(.smooth(duration: 0.3), value: nightTint)
                }
                SettingsRow(title: "Night mode", subtitle: "Hides the wallpaper and dims every card to one colour") {
                    PopupMenu(selection: $nightMode, choices: [Choice("Off", .off), Choice("On a Schedule", .scheduled), Choice("Always", .always)])
                }
                if nightMode == .scheduled {
                    SettingsRow(title: "From") { hourPicker("From", $nightStart) }
                    SettingsRow(title: "To") { hourPicker("To", $nightEnd) }
                }
                if nightMode != .off {
                    SettingsRow(title: "Colour", subtitle: "Red keeps your eyes used to the dark") {
                        Segmented(selection: $nightTint, choices: [Choice("Red", .red), Choice("Grey", .grey)])
                    }
                }
            }
            SettingsGroup(title: "Cards") {
                SettingsRow(title: "Material") {
                    Segmented(selection: $style, choices: GlassStyle.allCases.map { Choice($0.name, $0) })
                }
                if style == .liquid {
                    SettingsRow(title: "Tint", subtitle: "For clear or tinted glass, use System Settings › Appearance") {
                        Segmented(selection: $liquidTone, choices: [Choice("Dark", "dark"), Choice("Light", "light")])
                    }
                } else {
                    SettingsRow(title: "Frost", subtitle: "How blurred the wallpaper behind is") { slider("Frost", $frost) }
                    SettingsRow(title: "Transparency", subtitle: "How much of the wallpaper shows through") { slider("Transparency", $transparency) }
                    SettingsRow(title: "Tint", subtitle: "How dark the cards are") { slider("Tint", $tint) }
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: style)
        .animation(.smooth(duration: 0.3), value: nightMode)
        .animation(.smooth(duration: 0.3), value: clockColor)
    }

    private func hourPicker(_ title: String, _ value: Binding<Int>) -> some View {
        PopupMenu(selection: value, choices: (0..<24).map {
            Choice(Calendar.current.date(bySettingHour: $0, minute: 0, second: 0, of: .now)!.formatted(date: .omitted, time: .shortened), $0)
        })
    }

    private func slider(_ title: String, _ value: Binding<Double>) -> some View {
        GraphiteSlider(title: title, value: value)
    }
}

private struct WallpaperSettings: View {
    @AppStorage(AerialCatalog.selectionKey) private var wallpaper = AerialCatalog.defaultSelection

    var body: some View {
        SettingsPage {
            SettingsGroup(footer: "The aerials from System Settings › Wallpaper. Downloaded ones play from disk; the rest stream from Apple.") {
                SettingsRow(title: "Play", subtitle: "A new aerial each time Interlude starts") {
                    PopupMenu(selection: $wallpaper, choices:
                        [.heading("Shuffle"), Choice("All Aerials", "all")]
                        + AerialCatalog.categories.map { Choice("All \($0.name)", "category:\($0.id)") }
                        + AerialCatalog.categories.flatMap { category in
                            [Choice<String>.heading(category.name)] + category.aerials.map { Choice($0.name, "aerial:\($0.id)") }
                        })
                }
            }
            ForEach(AerialCatalog.categories) { category in
                VStack(alignment: .leading, spacing: 6) {
                    Text(category.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                        ForEach(category.aerials) { aerial in thumb(aerial, in: category) }
                    }
                }
            }
        }
    }

    /// An aerial's still with its name. Click to play only that one.
    private func thumb(_ aerial: AerialCatalog.Aerial, in category: AerialCatalog.Category) -> some View {
        let on = wallpaper == "aerial:\(aerial.id)" || wallpaper == "category:\(category.id)" || wallpaper == "all"
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button { wallpaper = "aerial:\(aerial.id)" } label: {
            Color.clear
                .frame(height: 118)
                .overlay {
                    AsyncImage(url: aerial.preview) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        PreviewBackdrop()
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text(aerial.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.top, 18)
                        .padding(.bottom, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.graphite, lineWidth: 2.5).opacity(wallpaper == "aerial:\(aerial.id)" ? 1 : 0))
                .opacity(on ? 1 : 0.55)
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(aerial.name)
        .accessibilityAddTraits(wallpaper == "aerial:\(aerial.id)" ? .isSelected : [])
    }
}

private struct MusicSettings: View {
    let model: OverlayModel
    @AppStorage(MusicLook.key) private var musicLook = MusicLook.album
    @AppStorage("monochromeArtwork") private var monochromeArtwork = true
    private let players = PlayerBridge()

    var body: some View {
        let grid = Grid.preview(u: 5.2)
        SettingsPage {
            // The real Now Playing card with the song playing now (a sample one when nothing plays).
            CardPreview(model: model, widget: .nowPlaying, size: .medium, style: 0, grid: grid)
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                // What sits behind the card while music plays: the album's colours, or the wallpaper.
                .background {
                    if musicLook == .album {
                        let source = model.nowPlaying.track == nil ? NowPlaying.sample : model.nowPlaying
                        MusicBackground(artwork: source.artwork, palette: source.palette, playing: true)
                    } else {
                        PreviewBackdrop()
                    }
                }
                .animation(.smooth(duration: 0.4), value: musicLook)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 6)
            SettingsGroup(title: "While Music Plays") {
                SettingsRow(title: "Background", subtitle: "What sits behind the Now Playing card") {
                    PopupMenu(selection: $musicLook, choices: [Choice("Album Colours", .album), Choice("Wallpaper", .wallpaper)])
                }
                SettingsRow(title: "Monochrome album art", subtitle: "Keeps the screen black and white") {
                    Toggle("Monochrome album art", isOn: $monochromeArtwork).labelsHidden()
                }
            }
            SettingsGroup(title: "Players", footer: "Interlude asks each player for access while it's open.") {
                ForEach(Track.Player.allCases, id: \.self) { player in
                    SettingsRow(title: player == .music ? "Music" : "Spotify") {
                        if players.permitted(player, ask: false) {
                            AllowedLabel()
                        } else {
                            Button("Allow…") { model.nowPlaying.requestPermissions() }
                                .buttonStyle(.capsule)
                        }
                    }
                }
            }
        }
    }
}

/// Settings for individual widgets: World Clock cities, the focus timer's length and Reminders.
private struct WidgetSettings: View {
    let model: OverlayModel
    @AppStorage(WorldCity.key) private var raw = WorldCity.defaults
    @AppStorage(FocusTimer.minutesKey) private var minutes = 25
    private static let zones = TimeZone.knownTimeZoneIdentifiers.sorted()

    var body: some View {
        let cities = WorldCity.load(raw)
        let grid = Grid.preview(u: 5.6)
        SettingsPage {
            // The real cards these settings change.
            HStack(spacing: grid.g) {
                CardPreview(model: model, widget: .worldClock, size: .medium, style: 0, grid: grid)
                CardPreview(model: model, widget: .timer, size: .small, style: 0, grid: grid)
                CardPreview(model: model, widget: .reminders, size: .small, style: 0, grid: grid)
            }
            .frame(maxWidth: .infinity)
            .frame(height: grid.s + 44)
            .background(PreviewBackdrop())
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Preview of the World Clock, Focus Timer and Reminders cards")
            SettingsGroup(title: "World Clock", footer: "Four cities, each with its own name and time zone.") {
                ForEach(cities.indices, id: \.self) { i in
                    HStack {
                        TextField("City \(i + 1)", text: Binding { cities[i].name } set: { edit(i) { $0.name = $1 }($0) })
                            .textFieldStyle(.plain)
                            .labelsHidden()
                        PopupMenu(selection: Binding { cities[i].zone } set: { edit(i) { $0.zone = $1 }($0) },
                                  choices: Self.zones.map { Choice($0.replacingOccurrences(of: "_", with: " "), $0) })
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                }
                HStack {
                    Spacer()
                    Button("Reset to Default") { raw = WorldCity.defaults }
                        .buttonStyle(.capsule)
                        .disabled(raw == WorldCity.defaults)
                }
                .padding(10)
            }
            SettingsGroup(title: "Focus Timer", footer: "Click the timer on the Interlude screen to start or pause it; right-click to reset. It chimes when it ends.") {
                SettingsRow(title: "Length") {
                    PopupMenu(selection: $minutes, choices: [5, 10, 15, 20, 25, 30, 45, 50, 60, 90].map { Choice("\($0) minutes", $0) })
                }
            }
            SettingsGroup(title: "Reminders", footer: "Click a circle on the Interlude screen to complete a reminder. Change the default list in Reminders › Settings.") {
                SettingsRow(title: "List", subtitle: "The first four unfinished reminders show") {
                    Text("Default list").foregroundStyle(.secondary)
                }
            }
        }
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

/// One permission: what it's for, and Allowed or a button that asks.
struct PermissionRow: View {
    let item: PermissionsModel.Item
    let fix: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            PaneIcon(symbol: item.symbol)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                Text(item.purpose).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if item.granted {
                AllowedLabel()
            } else {
                Button(item.canAsk ? "Allow…" : "Open Settings…", action: fix)
                    .buttonStyle(.capsule)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }
}

private struct PrivacySettings: View {
    let overlay: OverlayController
    @StateObject private var permissions: PermissionsModel
    @Environment(\.openWindow) private var openWindow

    init(overlay: OverlayController) {
        self.overlay = overlay
        _permissions = StateObject(wrappedValue: PermissionsModel(model: overlay.model))
    }

    var body: some View {
        SettingsPage {
            SettingsGroup(footer: "Interlude reads this on your Mac only, apart from your rough location going to the weather service. To take access back, use System Settings › Privacy & Security.") {
                ForEach(permissions.items) { item in
                    PermissionRow(item: item) { permissions.fix(item.id) }
                }
            }
            .padding(.top, 6)
            SettingsGroup {
                SettingsRow(title: "Replay the welcome tour") {
                    Button("Show Tour") { openWindow(id: OnboardingView.windowID) }
                        .buttonStyle(.capsule)
                }
            }
        }
        .onAppear { permissions.reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.reload() }
    }
}

/// What Interlude may access, for Settings › Privacy and the welcome window. Asks through the stores
/// the standby screen reads from, so they see the answer without a restart.
@MainActor
final class PermissionsModel: ObservableObject {
    enum Kind: String { case calendar, reminders, location, music }

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
    private let model: OverlayModel
    private let location = CLLocationManager()
    private let players = PlayerBridge()

    init(model: OverlayModel) { self.model = model }

    func reload() {
        let cal = EKEventStore.authorizationStatus(for: .event)
        let rem = EKEventStore.authorizationStatus(for: .reminder)
        let loc = location.authorizationStatus
        let music = Track.Player.allCases.contains { players.permitted($0, ask: false) }
        items = [
            Item(id: .calendar, name: "Calendar", purpose: "Shows your next event", symbol: "calendar",
                 granted: cal == .fullAccess, canAsk: cal == .notDetermined),
            Item(id: .reminders, name: "Reminders", purpose: "Lists what's due and lets you tick it off", symbol: "checklist",
                 granted: rem == .fullAccess, canAsk: rem == .notDetermined),
            Item(id: .location, name: "Location", purpose: "Weather for where you are", symbol: "location.fill",
                 granted: loc == .authorizedAlways || loc == .authorized, canAsk: loc == .notDetermined),
            Item(id: .music, name: "Music and Spotify", purpose: "Shows and controls what's playing. Asks while the player is open.",
                 symbol: "music.note", granted: music, canAsk: true),
        ]
    }

    func fix(_ kind: Kind) {
        guard let item = items.first(where: { $0.id == kind }) else { return }
        if item.canAsk {
            switch kind {
            case .calendar: model.calendar.requestAccess()
            case .reminders: model.reminders.requestAccess()
            case .location: model.weather.requestAccess()
            case .music: model.nowPlaying.requestPermissions()
            }
            // The system prompt waits for an answer, so check again for a while.
            Task {
                for _ in 0..<30 {
                    try? await Task.sleep(for: .seconds(1))
                    reload()
                    if items.first(where: { $0.id == kind })?.granted == true { break }
                }
            }
            return
        }
        let pane = switch kind {
        case .calendar: "Privacy_Calendars"
        case .reminders: "Privacy_Reminders"
        case .location: "Privacy_LocationServices"
        case .music: "Privacy_Automation"
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

