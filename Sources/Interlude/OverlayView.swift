import SwiftUI

/// How many rows of cards fill the screen: fewer rows, bigger cards. Picked in Settings › Layout.
enum GridSize {
    static let key = "gridRows"
    static let choices = [2, 3, 4]

    static var rows: Int {
        let r = UserDefaults.standard.integer(forKey: key)
        return choices.contains(r) ? r : 3
    }

    static func name(_ rows: Int) -> String {
        switch rows {
        case 2: "Large"
        case 4: "Compact"
        default: "Standard"
        }
    }
}

/// Sizes for the widget grid that covers the whole screen. The margin and the gap are the same
/// everywhere. The rows of cards exactly fill the height between the margins; the columns exactly fill
/// the width, so cells are a little wider or narrower than tall depending on the screen's shape.
struct Grid {
    let rows: Int
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
    var column: CGFloat { CGFloat(rows) * s + CGFloat(rows - 1) * g } // all the rows of cards
    var radius: CGFloat { 3.5 * u }

    init(size: CGSize, rows: Int = 3) {
        self.rows = rows
        width = size.width
        let margin = size.width * 0.035
        let u = (size.height - 2 * margin) / (CGFloat(rows) * 20 + CGFloat(rows - 1) * 1.4) // rows × 20u + gaps of 1.4u
        let usable = size.width - 2 * margin
        let cell = { (n: Int) in (usable - CGFloat(n - 1) * 1.4 * u) / CGFloat(n) }
        columns = (3...10).min { abs(cell($0) - 20 * u) < abs(cell($1) - 20 * u) }!
        cw = cell(columns)
        self.margin = margin
        self.u = u
    }

    /// Width and height of a card of this size.
    func w(_ size: WidgetSize) -> CGFloat { CGFloat(size.cols) * cw + CGFloat(size.cols - 1) * g }
    func h(_ size: WidgetSize) -> CGFloat { CGFloat(size.rows) * s + CGFloat(size.rows - 1) * g }

    func x(_ col: Int) -> CGFloat { margin + CGFloat(col) * (cw + g) }

    /// A small grid with unit `u`, the same shape as this Mac's screen, for card previews in Settings.
    static func preview(u: CGFloat) -> Grid {
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1710, height: 1112)
        let aspect = screen.width / screen.height
        let height = 62.8 * u / (1 - 0.07 * aspect)
        return Grid(size: CGSize(width: height * aspect, height: height))
    }
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
    @AppStorage(GridSize.key) private var gridRows = 3
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
            let grid = Grid(size: geo.size, rows: gridRows)
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

/// Widgets at their cells from Settings › Layout.
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
        let layout = stored.fitted(to: grid.columns, rows: grid.rows)
        ZStack(alignment: .topLeading) {
            ForEach(layout.placed) { widget in
                let o = layout.origin(of: widget)!
                WidgetCardView(model: model, widget: widget, size: layout.size(of: widget), style: layout.style(of: widget), grid: grid)
                    .hoverDetail(detail(widget), grid: grid)
                    .rise(1 + (Widget.allCases.firstIndex(of: widget) ?? 0), grid)
                    .transition(Motion.pop)
                    .offset(x: grid.x(o.col), y: grid.y(o.row))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.layout, value: layout)
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

/// Any widget's card at a size and style. Used on the standby screen, in Settings and by the renderer.
struct WidgetCardView: View {
    let model: OverlayModel
    let widget: Widget
    let size: WidgetSize
    let style: Int
    let grid: Grid
    @ObservedObject private var nowPlaying: NowPlaying
    @ObservedObject private var calendar: CalendarStore

    init(model: OverlayModel, widget: Widget, size: WidgetSize, style: Int, grid: Grid) {
        self.model = model
        self.widget = widget
        self.size = size
        self.style = style
        self.grid = grid
        nowPlaying = model.nowPlaying
        calendar = model.calendar
    }

    @Environment(\.previewMusic) private var previewMusic

    var body: some View {
        switch widget {
        case .battery: BatteryCard(battery: model.battery, grid: grid, size: size, style: style)
        case .calendar: CalendarCard(calendar: calendar, grid: grid, size: size, style: style)
        case .nowPlaying: NowPlayingCard(nowPlaying: nowPlaying, grid: grid, size: size, style: style)
        case .clock: ClockCard(weather: model.weather, grid: grid, size: size, style: style, nextEvent: calendar.next,
                               musicColor: nowPlaying.visible || previewMusic ? nowPlaying.palette.accent : nil)
        case .weather: WeatherCard(weather: model.weather, grid: grid, size: size, style: style)
        case .reminders: RemindersCard(reminders: model.reminders, grid: grid, size: size, style: style)
        case .worldClock: WorldClockCard(grid: grid, size: size, style: style)
        case .timer: TimerCard(timer: model.timer, grid: grid, size: size, style: style)
        }
    }
}

struct ClockCard: View {
    @ObservedObject var weather: WeatherStore
    let grid: Grid
    var size: WidgetSize = .medium
    var style = 0
    /// Shown under the large stacked clock.
    var nextEvent: CalendarStore.Event? = nil
    /// The music's colour, when "Match Music" should use it.
    var musicColor: Color? = nil
    @AppStorage(ClockFont.key) private var savedFont = ClockFont.sfPro
    @Environment(\.clockFontOverride) private var fontOverride
    /// The font from Settings, unless a preview asks for a particular one.
    private var clockFont: ClockFont { fontOverride ?? savedFont }
    @AppStorage(ClockColor.key) private var colorChoice = ClockColor.white
    @AppStorage(ClockColor.customKey) private var customColor = ""

    private var timeColor: Color {
        switch colorChoice {
        case .white: .white
        case .music: musicColor ?? .white
        case .custom: ClockColor.custom(from: customColor)
        }
    }

    /// Card unit from the clock-fonts mockup, where the medium card is 26.43 units tall. Everything in
    /// this card is sized in it, so the card matches the mockup at any screen size.
    private var k: CGFloat { grid.s / 26.43 }
    private var analog: Bool { (size == .small || size == .large) && style == 1 }

    /// The time in the chosen clock font, `scale` times the medium card's size. The negative bottom
    /// padding matches the mockup's CSS line height: (line height − ascent − descent) / 2.
    @ViewBuilder private func time(_ text: String, _ scale: CGFloat) -> some View {
        Group {
            switch clockFont {
            case .sfPro: // line height 0.85, ascent 0.967, descent 0.211
                RollingText(text: text, distance: 6 * k * scale, tracking: -0.4 * k * scale)
                    .font(.system(size: 12.5 * k * scale, weight: .medium))
                    .padding(.bottom, -0.164 * 12.5 * k * scale)
            case .instrumentSerif: // line height 0.75, ascent 0.99, descent 0.31
                RollingText(text: text, distance: 6 * k * scale, tracking: -0.2 * k * scale)
                    .font(.custom("Instrument Serif", size: 15.5 * k * scale))
                    .padding(.bottom, -0.275 * 15.5 * k * scale)
            }
        }
        .monospacedDigit()
        .foregroundStyle(timeColor)
        .animation(.smooth(duration: 0.8), value: timeColor)
        .lineLimit(1)
        .fixedSize()
    }

    /// Hours over minutes, close together. The line boxes are taller than the digits, so the gap is
    /// negative: about a tenth of the digit height between the lines, in either font.
    private func stacked(_ date: Date, _ scale: CGFloat) -> some View {
        let gap = clockFont == .sfPro ? -0.17 * 12.5 * k * scale : -0.08 * 15.5 * k * scale
        return VStack(alignment: .leading, spacing: gap) {
            time(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted))), scale)
            time(date.formatted(.dateTime.minute(.twoDigits)), scale)
        }
    }

    /// "Wed 28 Oct": short, no comma.
    private static let dateFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// Temperature on the left, date on the right, in small DM Mono.
    private func header(_ date: Date, scale: CGFloat = 1, dateText: String? = nil, extra: String? = nil) -> some View {
        HStack {
            // Empty state: no weather yet, nothing shown.
            if let temperature = weather.temperature {
                HStack(spacing: 0.6 * k * scale) {
                    Image(systemName: weather.symbol).font(.system(size: 1.7 * k * scale, weight: .medium))
                    RollingText(text: "\(temperature)°", distance: 1 * k, tracking: 0)
                    if let extra { Text(extra).lineLimit(1) }
                }
            }
            Spacer(minLength: 0)
            Text(dateText ?? Self.dateFormat.string(from: date)).opacity(0.75).lineLimit(1)
        }
        .font(.custom("DM Mono", size: 1.7 * k * scale)) // small labels: DM Mono
    }

    var body: some View {
        Group {
            if analog {
                TimelineView(.periodic(from: .now, by: 1)) { content($0.date) }
            } else {
                TimelineView(.everyMinute) { content($0.date) }
            }
        }
        .frame(width: grid.w(size), height: grid.h(size))
        .glass(grid)
    }

    @ViewBuilder private func content(_ date: Date) -> some View {
        let hm = date.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
        switch (size, style) {
        case (.small, 1), (.large, 1):
            AnalogFace(date: date, zone: .current, size: min(grid.w(size), grid.h(size)) - 3 * grid.u)
        case (.small, _):
            VStack(alignment: .leading, spacing: 0) {
                header(date, scale: 0.8, dateText: date.formatted(.dateTime.weekday(.abbreviated)))
                Spacer(minLength: 0)
                stacked(date, clockFont == .sfPro ? 0.66 : 0.64)
            }
            .padding(1.8 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
        case (.medium, 1):
            VStack(spacing: 2 * k) {
                time(hm, 1)
                Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.custom("DM Mono", size: 1.7 * k))
                    .opacity(0.75)
            }
        case (.medium, _):
            VStack(alignment: .leading, spacing: 0) {
                header(date)
                Spacer(minLength: 0)
                time(hm, 1)
            }
            .padding(.vertical, 1.8 * k)
            .padding(.horizontal, 2.2 * k)
        case (.large, _):
            VStack(alignment: .leading, spacing: 0) {
                header(date, scale: 1.1, extra: weather.city)
                Spacer(minLength: 0)
                stacked(date, clockFont == .sfPro ? 1.45 : 1.4)
                if let nextEvent {
                    Text("Next · \(nextEvent.title) \(nextEvent.start.formatted(date: .omitted, time: .shortened))")
                        .font(.custom("DM Mono", size: 1.6 * k))
                        .opacity(0.6)
                        .lineLimit(1)
                        .padding(.top, 2 * k)
                }
            }
            .padding(2.2 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
        case (.extraLarge, 1):
            VStack(spacing: 3 * k) {
                time(hm, 2.3)
                HStack(spacing: 5 * k) {
                    if let t = weather.temperature { Label("\(t)° \(weather.condition)", systemImage: weather.symbol) }
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide))).opacity(0.75)
                    if let nextEvent { Text("\(nextEvent.title) · \(nextEvent.start.formatted(date: .omitted, time: .shortened))") }
                }
                .font(.custom("DM Mono", size: 1.9 * k))
                .lineLimit(1)
            }
        case (.extraLarge, _):
            VStack(alignment: .leading, spacing: 0) {
                header(date, scale: 1.2,
                       dateText: date.formatted(.dateTime.weekday(.wide).day().month(.wide)),
                       extra: weather.high.flatMap { h in weather.low.map { "· H\(h) L\($0)" } })
                Spacer(minLength: 0)
                time(hm, 2.9)
            }
            .padding(.vertical, 2.4 * k)
            .padding(.horizontal, 3 * k)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct BatteryCard: View {
    @ObservedObject var battery: BatteryMonitor
    let grid: Grid
    var size: WidgetSize = .small
    var style = 0

    private var items: [BatteryMonitor.Device] {
        [BatteryMonitor.Device(name: "Mac", level: battery.level, symbol: "laptopcomputer")] + battery.devices.prefix(3)
    }

    var body: some View {
        Group {
            switch (size, style) {
            case (.small, 1) where !battery.devices.isEmpty: devices
            case (.small, _): single
            case (_, 1): list
            default: row
            }
        }
        .frame(width: grid.w(size), height: grid.h(size))
        .glass(grid)
        .animation(.smooth(duration: 0.8), value: battery.devices)
    }

    private func ring(_ item: BatteryMonitor.Device, _ ring: CGFloat) -> some View {
        ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: ring * 0.09)
            Circle()
                .trim(from: 0, to: item.level)
                .stroke(.white, style: StrokeStyle(lineWidth: ring * 0.09, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: item.symbol).font(.system(size: ring * 0.34))
        }
        .padding(ring * 0.045)
        .frame(width: ring, height: ring)
        .accessibilityElement()
        .accessibilityLabel("\(item.name), \(Int((item.level * 100).rounded())) percent")
    }

    /// Up to four rings, Mac first, like the Batteries widget.
    private var devices: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1.2 * grid.u) {
            ForEach(items) { ring($0, 7 * grid.u) }
        }
        .padding(1.8 * grid.u)
    }

    /// Rings in a row with the percentage under each.
    private var row: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                VStack(spacing: 0.8 * grid.u) {
                    ring(item, 7.4 * grid.u)
                    Text(item.level.formatted(.percent.precision(.fractionLength(0))))
                        .font(.system(size: 1.6 * grid.u, weight: .medium))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(1.8 * grid.u)
    }

    /// Two columns of name, percentage and a bar.
    private var list: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 2.4 * grid.u), GridItem(.flexible())], spacing: 1.6 * grid.u) {
            ForEach(items) { item in
                VStack(spacing: 0.6 * grid.u) {
                    HStack {
                        Text(item.name).fontWeight(.semibold).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(item.level.formatted(.percent.precision(.fractionLength(0)))).monospacedDigit()
                    }
                    .font(.system(size: 1.6 * grid.u))
                    Bar(fraction: item.level, height: 0.45 * grid.u)
                }
            }
        }
        .padding(2.2 * grid.u)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A thin white bar on a faint track, filled to a fraction.
struct Bar: View {
    let fraction: Double
    let height: CGFloat
    var from: Double = 0

    var body: some View {
        Capsule().fill(.white.opacity(0.25))
            .frame(height: height)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(.white)
                        .frame(width: geo.size.width * max(0, min(1, fraction - from)))
                        .offset(x: geo.size.width * max(0, min(1, from)))
                }
            }
    }
}

struct CalendarCard: View {
    @ObservedObject var calendar: CalendarStore
    let grid: Grid
    var size: WidgetSize = .small
    var style = 0
    private static let weekdays = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(context.date)
                .padding(1.8 * grid.u)
                .frame(width: grid.w(size), height: grid.h(size), alignment: .topLeading)
                .glass(grid)
        }
    }

    @ViewBuilder private func content(_ date: Date) -> some View {
        let u = grid.u
        switch (size, style) {
        case (.small, 1):
            VStack(alignment: .leading, spacing: 0) {
                dayLabel(date)
                Text(date, format: .dateTime.day()).font(.system(size: 6 * u, weight: .light))
                Spacer(minLength: 0)
                if let next = calendar.next { event(next, first: true, range: false) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case (.small, _):
            month(date, scale: 1)
        case (.medium, 1):
            HStack(alignment: .top, spacing: 2 * u) {
                month(date, scale: 1).frame(width: grid.cw - 3.6 * u)
                events(Array(calendar.today.prefix(2)), range: false)
            }
        case (.medium, _):
            HStack(alignment: .top, spacing: 2 * u) {
                VStack(alignment: .leading, spacing: 0) {
                    dayLabel(date)
                    Text(date, format: .dateTime.day()).font(.system(size: 5.4 * u, weight: .light))
                }
                .frame(width: 10 * u, alignment: .leading)
                events(Array(calendar.today.prefix(3)), range: true)
            }
        case (.large, 1):
            agenda(date)
        case (.large, _):
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(date, format: .dateTime.month(.wide).year())
                        .textCase(.uppercase)
                        .font(.system(size: 1.4 * u, weight: .bold))
                        .tracking(0.08 * u)
                        .opacity(0.6)
                    Spacer()
                    let n = calendar.today.count
                    Text(n == 0 ? "No more events today" : n == 1 ? "1 event today" : "\(n) events today")
                        .font(.system(size: 1.4 * u)).opacity(0.6)
                }
                month(date, scale: 1.6, label: false).padding(.vertical, 1 * u)
                if let next = calendar.next {
                    Divider().overlay(.white.opacity(0.2))
                    HStack(spacing: 0.6 * u) {
                        Text(next.title).fontWeight(.semibold).lineLimit(1)
                        Text("· " + next.start.formatted(date: .omitted, time: .shortened)).opacity(0.6)
                    }
                    .font(.system(size: 1.6 * u))
                    .padding(.top, 1 * u)
                }
            }
        default:
            month(date, scale: 1)
        }
    }

    private func dayLabel(_ date: Date) -> some View {
        Text(date, format: .dateTime.weekday(.wide))
            .textCase(.uppercase)
            .font(.system(size: 1.35 * grid.u, weight: .bold))
            .tracking(0.08 * grid.u)
            .opacity(0.6)
    }

    /// An event with a white bar on its left: white for the next one, faint for the rest.
    private func event(_ e: CalendarStore.Event, first: Bool, range: Bool) -> some View {
        let time = e.start.formatted(date: .omitted, time: .shortened)
        return VStack(alignment: .leading, spacing: 0.1 * grid.u) {
            Text(e.title).fontWeight(.semibold).lineLimit(1)
            Text(range ? e.end.map { "\(time) – \($0.formatted(date: .omitted, time: .shortened))" } ?? time : time)
                .opacity(0.6).lineLimit(1)
        }
        .font(.system(size: 1.5 * grid.u))
        .padding(.leading, 0.9 * grid.u)
        .overlay(alignment: .leading) {
            Capsule().fill(.white.opacity(first ? 1 : 0.4)).frame(width: 0.25 * grid.u)
        }
    }

    @ViewBuilder private func events(_ list: [CalendarStore.Event], range: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1 * grid.u) {
            if list.isEmpty {
                Text("No more events today").font(.system(size: 1.5 * grid.u)).opacity(0.6)
            }
            ForEach(Array(list.enumerated()), id: \.element) { i, e in event(e, first: i == 0, range: range) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The week ahead, one row per day with its events.
    private func agenda(_ date: Date) -> some View {
        let cal = Calendar.current
        let days = (0..<5).compactMap { cal.date(byAdding: .day, value: $0, to: cal.startOfDay(for: date)) }
        let u = grid.u
        return VStack(alignment: .leading, spacing: 0.9 * u) {
            Text("THIS WEEK").font(.system(size: 1.35 * u, weight: .bold)).tracking(0.08 * u).opacity(0.6)
            ForEach(days, id: \.self) { day in
                let list = calendar.upcoming.filter { cal.isDate($0.start, inSameDayAs: day) }.prefix(3)
                VStack(alignment: .leading, spacing: 0.7 * u) {
                    Divider().overlay(.white.opacity(0.15))
                    HStack(alignment: .top, spacing: 1 * u) {
                        Text(day, format: .dateTime.weekday(.abbreviated).day())
                            .fontWeight(.semibold)
                            .opacity(cal.isDateInToday(day) ? 1 : 0.6)
                            .frame(width: 7 * u, alignment: .leading)
                        VStack(alignment: .leading, spacing: 0.3 * u) {
                            if list.isEmpty { Text("No events").opacity(0.5) }
                            ForEach(Array(list), id: \.self) { e in
                                HStack(spacing: 0.6 * u) {
                                    Text(e.title).lineLimit(1)
                                    Text(e.start.formatted(date: .omitted, time: .shortened)).opacity(0.6)
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 1.5 * u))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func month(_ date: Date, scale m: CGFloat, label: Bool = true) -> some View {
        let today = Calendar.current.component(.day, from: date)
        let days = MonthGrid.days(for: date)
        let rows = stride(from: 0, to: days.count, by: 7).map { start in
            (start..<start + 7).map { $0 < days.count ? days[$0] : nil }
        }
        return VStack(alignment: .leading, spacing: 0) {
            if label {
                Text(date, format: .dateTime.month(.wide))
                    .textCase(.uppercase)
                    .font(.system(size: 1.35 * grid.u, weight: .bold))
                    .tracking(0.05 * grid.u)
                    .padding(.leading, 0.6 * grid.u)
                    .padding(.bottom, 0.3 * grid.u)
            }
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
                        DayCell(day: rows[r][c], isToday: rows[r][c] == today, isWeekend: c >= 5, side: 2.1 * grid.u * m)
                    }
                }
            }
        }
        .font(.system(size: 1.3 * grid.u * m, weight: .semibold))
        .monospacedDigit()
    }
}

private struct DayCell: View {
    let day: Int?
    let isToday: Bool
    let isWeekend: Bool
    let side: CGFloat

    var body: some View {
        Text(day.map(String.init) ?? "")
            .foregroundStyle(isToday ? Color(white: 0.17) : .white.opacity(isWeekend ? 0.5 : 1))
            .frame(width: side, height: side)
            .background { if isToday { Circle().fill(.white) } }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
