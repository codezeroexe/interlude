import SwiftUI

/// Sizes for the widget grid that covers the whole screen. The margin and the gap are the same
/// everywhere. Three rows of cards exactly fill the height between the margins; the columns exactly fill
/// the width, so cells are a little wider or narrower than tall depending on the screen's shape.
struct Grid {
    let u: CGFloat
    let margin: CGFloat
    let width: CGFloat
    /// Number of columns: whichever count makes cells closest to square.
    let columns: Int
    /// Cell width.
    let cw: CGFloat
    var s: CGFloat { 20 * u }          // cell height
    var g: CGFloat { 1.4 * u }         // gap between cells
    var wide: CGFloat { 2 * cw + g }   // wide card: two cells
    var column: CGFloat { 3 * s + 2 * g } // three rows of cards
    var radius: CGFloat { 3.5 * u }

    init(size: CGSize) {
        width = size.width
        let margin = size.width * 0.035
        let u = (size.height - 2 * margin) / 62.8 // 3 × 20u + 2 × 1.4u
        let usable = size.width - 2 * margin
        let cell = { (n: Int) in (usable - CGFloat(n - 1) * 1.4 * u) / CGFloat(n) }
        columns = (3...10).min { abs(cell($0) - 20 * u) < abs(cell($1) - 20 * u) }!
        cw = cell(columns)
        self.margin = margin
        self.u = u
    }

    func x(_ col: Int) -> CGFloat { margin + CGFloat(col) * (cw + g) }
    func y(_ row: Int) -> CGFloat { margin + CGFloat(row) * (s + g) }
}

struct OverlayView: View {
    let model: OverlayModel
    let dismiss: () -> Void
    @ObservedObject private var nowPlaying: NowPlaying
    @AppStorage(MusicLook.key) private var musicLook = MusicLook.album
    @ObservedObject private var entrance: Entrance
    @ObservedObject private var night: NightMonitor
    @AppStorage(NightMode.tintKey) private var nightTint = NightTint.red
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(model: OverlayModel, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
        nowPlaying = model.nowPlaying
        entrance = model.entrance
        night = model.night
    }

    var body: some View {
        // Music mode: while music plays (or for 5 min after pausing) the album look swaps the aerial
        // for the album backdrop; the wallpaper look keeps the aerial.
        let music = nowPlaying.visible
        // Night mode: no wallpaper, and every card in one dim colour.
        let albumBackdrop = music && musicLook == .album && !night.on
        GeometryReader { geo in
            let grid = Grid(size: geo.size)
            ZStack {
                // Wallpaper: fades in while settling from a slight zoom; fades out on exit.
                ZStack {
                    AerialView(player: model.aerial.player)
                        .opacity(albumBackdrop || night.on ? 0 : 1)
                    if albumBackdrop {
                        MusicBackground(artwork: nowPlaying.artwork, palette: nowPlaying.palette, playing: nowPlaying.track?.playing == true)
                            .transition(.opacity)
                    }
                }
                .background(.black)
                .opacity(entrance.shown ? 1 : 0)
                .scaleEffect(entrance.shown || reduceMotion ? 1 : 1.06)
                .animation(entrance.shown ? .smooth(duration: 1.1) : .easeIn(duration: 0.4).delay(0.2), value: entrance.shown)

                // Click on empty wallpaper closes the overlay.
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismiss)

                WidgetCanvas(model: model, nowPlaying: nowPlaying, night: night.on, grid: grid, dismiss: dismiss)
                    .compositingGroup()
                    .grayscale(night.on ? 1 : 0)
                    .colorMultiply(night.on ? nightTint.color : .white)
                    .opacity(night.on ? 0.7 : 1)
            }
            .animation(.easeInOut(duration: 1.5), value: night.on)
            .animation(.easeInOut(duration: 1.2), value: music)
            .animation(.easeInOut(duration: 1.2), value: musicLook)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .environmentObject(model.entrance)
        .onChange(of: albumBackdrop || night.on, initial: true) { _, hidden in hidden ? model.aerial.pause() : model.aerial.play() }
    }
}

/// Top-left row: next calendar event, then one pill per app with notifications.
struct PillsRow: View {
    let model: OverlayModel
    @ObservedObject var calendar: CalendarStore
    @ObservedObject var notifications: NotificationStore
    let grid: Grid
    let dismiss: () -> Void

    var body: some View {
        if calendar.next != nil || !notifications.groups.isEmpty {
            HStack(spacing: 1.2 * grid.u) {
                NextEventPill(calendar: calendar, grid: grid)
                ForEach(notifications.groups) { group in
                    NotificationPill(group: group, grid: grid,
                                     open: { dismiss(); NotificationPill.openApp(group.bundleID) },
                                     dismiss: { notifications.dismiss(group) },
                                     hideApp: { notifications.hideApp(group) })
                }
            }

            .transition(Motion.pop)
        }
    }
}

/// Widgets at their cells from Settings › Layout, and the pills in the space they leave free.
/// Now Playing keeps its cell while hidden, so nothing jumps when music stops.
struct WidgetCanvas: View {
    let model: OverlayModel
    @ObservedObject var nowPlaying: NowPlaying
    let night: Bool
    let grid: Grid
    let dismiss: () -> Void
    @ObservedObject private var battery: BatteryMonitor
    @ObservedObject private var calendar: CalendarStore
    @ObservedObject private var weather: WeatherStore
    @ObservedObject private var reminders: ReminderStore
    // Read so the canvas redraws when any layout changes in Settings.
    @AppStorage(LayoutProfile.standard.key) private var standard = WidgetLayout.standard(columns: 5)
    @AppStorage(LayoutProfile.music.key) private var music = WidgetLayout.standard(columns: 5)
    @AppStorage(LayoutProfile.night.key) private var nightLayout = WidgetLayout.standard(columns: 5)
    @AppStorage(LayoutProfile.music.enabledKey) private var musicOn = false
    @AppStorage(LayoutProfile.night.enabledKey) private var nightOn = false

    init(model: OverlayModel, nowPlaying: NowPlaying, night: Bool, grid: Grid, dismiss: @escaping () -> Void) {
        self.model = model
        self.nowPlaying = nowPlaying
        self.night = night
        self.grid = grid
        self.dismiss = dismiss
        battery = model.battery
        calendar = model.calendar
        weather = model.weather
        reminders = model.reminders
    }

    var body: some View {
        let stored: WidgetLayout = switch LayoutProfile.active(music: nowPlaying.visible, night: night) {
        case .standard: standard
        case .music: music
        case .night: nightLayout
        }
        let layout = stored.fitted(to: grid.columns)
        let pills = grid.pillsArea(layout)
        ZStack(alignment: .topLeading) {
            PillsRow(model: model, calendar: model.calendar, notifications: model.notifications, grid: grid, dismiss: dismiss)
                .rise(0, grid)
                .frame(width: pills.width, height: grid.s, alignment: pills.alignment)
                .offset(x: pills.x, y: pills.y)
            ForEach(layout.placed) { widget in
                if widget != .nowPlaying || nowPlaying.visible {
                    let o = layout.origin(of: widget)!
                    card(widget)
                        .hoverDetail(detail(widget), grid: grid)
                        .rise(1 + (Widget.allCases.firstIndex(of: widget) ?? 0), grid)
                        .transition(Motion.pop)
                        .offset(x: grid.x(o.col), y: grid.y(o.row))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.layout, value: layout)
    }

    @ViewBuilder private func card(_ widget: Widget) -> some View {
        switch widget {
        case .battery: BatteryCard(battery: model.battery, grid: grid)
        case .calendar: CalendarCard(grid: grid)
        case .nowPlaying: NowPlayingCard(nowPlaying: nowPlaying, grid: grid)
        case .clock: ClockCard(weather: model.weather, grid: grid, musicColor: nowPlaying.visible ? nowPlaying.palette.accent : nil)
        case .weather: WeatherCard(weather: model.weather, grid: grid)
        case .reminders: RemindersCard(reminders: model.reminders, grid: grid)
        case .worldClock: WorldClockCard(grid: grid)
        case .timer: TimerCard(timer: model.timer, grid: grid)
        }
    }

    /// The extra line a card shows while the pointer is over it.
    private func detail(_ widget: Widget) -> String? {
        switch widget {
        case .battery: battery.detail
        case .calendar:
            calendar.next.map { "\($0.title) at \($0.start.formatted(date: .omitted, time: .shortened))" } ?? "No more events today"
        case .clock: Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .weather:
            [weather.feelsLike.map { "Feels like \($0)°" }, weather.wind.map { "Wind \($0) \(Locale.current.measurementSystem == .us ? "mph" : "km/h")" },
             weather.humidity.map { "Humidity \($0)%" }].compactMap { $0 }.joined(separator: " · ")
        case .reminders: reminders.overdue > 0 ? "\(reminders.overdue) overdue" : "Click a circle to complete it"
        case .timer: "Click to start or pause · right-click to reset"
        case .nowPlaying, .worldClock: nil
        }
    }
}

// MARK: - Cards

struct ClockCard: View {
    @ObservedObject var weather: WeatherStore
    let grid: Grid
    /// The music's colour, when "Match Music" should use it.
    var musicColor: Color? = nil
    @AppStorage(ClockFont.key) private var clockFont = ClockFont.sfPro
    @AppStorage(ClockColor.key) private var colorChoice = ClockColor.white
    @AppStorage(ClockColor.customKey) private var customColor = ""

    private var timeColor: Color {
        switch colorChoice {
        case .white: .white
        case .music: musicColor ?? .white
        case .custom: ClockColor.custom(from: customColor)
        }
    }

    /// Card unit from the clock-fonts mockup, where the card is 26.43 units tall. Everything in this
    /// card is sized in it, so the card matches the mockup at any screen size.
    private var k: CGFloat { grid.s / 26.43 }

    /// The big time in the chosen clock font. The negative bottom padding matches the mockup's CSS
    /// line height: (line height − ascent − descent) / 2, from each font's metrics.
    @ViewBuilder private func time(_ date: Date) -> some View {
        let text = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        switch clockFont {
        case .sfPro: // line height 0.85, ascent 0.967, descent 0.211
            RollingText(text: text, distance: 6 * k, tracking: -0.4 * k)
                .font(.system(size: 12.5 * k, weight: .medium))
                .padding(.bottom, -0.164 * 12.5 * k)
        case .instrumentSerif: // line height 0.75, ascent 0.99, descent 0.31
            RollingText(text: text, distance: 6 * k, tracking: -0.2 * k)
                .font(.custom("Instrument Serif", size: 15.5 * k))
                .padding(.bottom, -0.275 * 15.5 * k)
        }
    }

    /// "Wed 28 Oct": short, no comma.
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    var body: some View {
        TimelineView(.everyMinute) { context in
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    // Empty state: no weather yet, nothing shown.
                    if let temperature = weather.temperature {
                        HStack(spacing: 0.6 * k) {
                            Image(systemName: weather.symbol).font(.system(size: 1.7 * k, weight: .medium))
                            RollingText(text: "\(temperature)°", distance: 1 * k, tracking: 0)
                        }
                    }
                    Spacer()
                    Text(Self.dateFormat.string(from: context.date))
                        .opacity(0.75)
                }
                .font(.custom("DM Mono", size: 1.7 * k)) // small labels: DM Mono
                Spacer(minLength: 0)
                time(context.date)
                    .monospacedDigit()
                    .foregroundStyle(timeColor)
                    .animation(.smooth(duration: 0.8), value: timeColor)
                    .lineLimit(1)
            }
            .padding(.vertical, 1.8 * k)
            .padding(.horizontal, 2.2 * k)
            .frame(width: grid.wide, height: grid.s)
            .glass(grid)
        }
    }
}

struct BatteryCard: View {
    @ObservedObject var battery: BatteryMonitor
    let grid: Grid

    var body: some View {
        if battery.devices.isEmpty {
            single
        } else {
            devices
        }
    }

    /// With Bluetooth devices connected: up to four rings, Mac first, like the Batteries widget.
    private var devices: some View {
        let items = [BatteryMonitor.Device(name: "Mac", level: battery.level, symbol: "laptopcomputer")] + battery.devices.prefix(3)
        let ring = 7 * grid.u
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1.2 * grid.u) {
            ForEach(items) { item in
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: ring * 0.09)
                    Circle()
                        .trim(from: 0, to: item.level)
                        .stroke(.white, style: StrokeStyle(lineWidth: ring * 0.09, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: item.symbol).font(.system(size: 2.4 * grid.u))
                }
                .padding(ring * 0.045)
                .frame(width: ring, height: ring)
                .accessibilityElement()
                .accessibilityLabel("\(item.name), \(Int((item.level * 100).rounded())) percent")
            }
        }
        .padding(1.8 * grid.u)
        .frame(width: grid.cw, height: grid.s)
        .glass(grid)
        .animation(.smooth(duration: 0.8), value: battery.devices)
    }

    private var single: some View {
        let ring = 8.5 * grid.u
        let line = ring * 0.09
        // Charging leaves a 30° gap at the top for the bolt.
        let span = battery.pluggedIn ? 330.0 / 360 : 1
        let start = battery.pluggedIn ? -75.0 : -90.0
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Circle()
                    .trim(from: 0, to: span)
                    .stroke(.white.opacity(0.2), style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(start))
                Circle()
                    .trim(from: 0, to: span * battery.level)
                    .stroke(.white, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(start))
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 3.4 * grid.u, weight: .regular))
                if battery.pluggedIn {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 2.1 * grid.u, weight: .bold))
                        .offset(y: -ring / 2)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(line / 2)
            .frame(width: ring, height: ring)
            .animation(.smooth(duration: 0.8), value: battery.level)
            .animation(.spring(duration: 0.4, bounce: 0.4), value: battery.pluggedIn)

            Spacer(minLength: 0)

            RollingText(text: battery.level.formatted(.percent.precision(.fractionLength(0))), distance: 3 * grid.u, tracking: -0.2 * grid.u)
                .font(.system(size: 6 * grid.u, weight: .medium))
                .monospacedDigit()
                .padding(.bottom, -0.8 * grid.u)
        }
        .padding(1.8 * grid.u)
        .frame(width: grid.cw, height: grid.s, alignment: .leading)
        .glass(grid)
    }
}

struct CalendarCard: View {
    let grid: Grid
    private static let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        TimelineView(.everyMinute) { context in
            let today = Calendar.current.component(.day, from: context.date)
            let days = MonthGrid.days(for: context.date)
            let rows = stride(from: 0, to: days.count, by: 7).map { start in
                (start..<start + 7).map { $0 < days.count ? days[$0] : nil }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(context.date, format: .dateTime.month(.wide))
                    .textCase(.uppercase)
                    .font(.system(size: 1.35 * grid.u, weight: .bold))
                    .tracking(0.05 * grid.u)
                    .padding(.leading, 0.6 * grid.u)
                    .padding(.bottom, 0.3 * grid.u)
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { c in
                        Text(Self.weekdays[c])
                            .foregroundStyle(.white.opacity(c >= 5 ? 0.45 : 0.7))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                ForEach(rows.indices, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { c in
                            DayCell(day: rows[r][c], isToday: rows[r][c] == today, isWeekend: c >= 5, grid: grid)
                        }
                    }
                }
            }
            .font(.system(size: 1.3 * grid.u, weight: .semibold))
            .monospacedDigit()
            .padding(1.8 * grid.u)
            .frame(width: grid.cw, height: grid.s)
            .glass(grid)
        }
    }
}

private struct DayCell: View {
    let day: Int?
    let isToday: Bool
    let isWeekend: Bool
    let grid: Grid

    var body: some View {
        Text(day.map(String.init) ?? "")
            .foregroundStyle(isToday ? Color(white: 0.17) : .white.opacity(isWeekend ? 0.5 : 1))
            .frame(width: 2.1 * grid.u, height: 2.1 * grid.u)
            .background { if isToday { Circle().fill(.white) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct NextEventPill: View {
    @ObservedObject var calendar: CalendarStore
    let grid: Grid

    var body: some View {
        // Empty state: no event, no pill.
        if let event = calendar.next {
            HStack(spacing: 1 * grid.u) {
                Image(systemName: "calendar")
                Text(event.title).lineLimit(1)
                Text(event.start, format: .dateTime.hour().minute()).opacity(0.7)
            }
            .font(.system(size: 1.8 * grid.u, weight: .semibold))
            .padding(.horizontal, 2 * grid.u)
            .padding(.vertical, 1.2 * grid.u)
            .glass(grid, capsule: true)
        }
    }
}

// MARK: - Style and motion

extension View {
    /// Entrance: cards rise in one after another, 70 ms apart, after the wallpaper fades in.
    func rise(_ index: Int, _ grid: Grid) -> some View {
        modifier(Rise(index: index, distance: 2 * grid.u))
    }
}

/// Flips to true just after the overlay window appears; cards animate in on that change.
/// (A model object, not @State: the CommandLineTools SDK lacks the SwiftUI macro plugin.)
@MainActor
final class Entrance: ObservableObject {
    @Published var shown = false
}

private struct Rise: ViewModifier {
    let index: Int
    let distance: CGFloat
    @EnvironmentObject private var entrance: Entrance
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = entrance.shown
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance)
            .scaleEffect(shown || reduceMotion ? 1 : 0.97)
            // In: rise one after another once the wallpaper is fading in. Out: quick drop, same order.
            .animation(shown ? .smooth(duration: 0.7).delay(0.3 + Double(index) * 0.07)
                             : .easeIn(duration: 0.28).delay(Double(index) * 0.03), value: shown)
    }
}

/// How music mode looks; picked in the menu bar.
enum MusicLook: String {
    static let key = "musicLook"
    /// Animated backdrop in the album's colours.
    case album
    /// Keep the aerial. Raw value kept from the old lyrics-panel look so saved settings still load.
    case wallpaper = "panel"
}
