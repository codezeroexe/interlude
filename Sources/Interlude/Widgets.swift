import AppKit
import EventKit
import SwiftUI

// Cards modelled on the macOS desktop widgets: Weather (medium), Reminders (medium),
// World Clock (medium, four faces) and a Timer (small).

// MARK: - Weather

/// Like the Weather widget: place, temperature, condition, high and low, then the next hours,
/// in white on glass like every other card.
struct WeatherCard: View {
    @ObservedObject var weather: WeatherStore
    let grid: Grid

    var body: some View {
        let u = grid.u
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0.4 * u) {
                        Text(weather.city ?? "My Location")
                        Image(systemName: "location.fill").font(.system(size: 1.1 * u))
                    }
                    .font(.system(size: 1.8 * u, weight: .semibold))
                    RollingText(text: weather.temperature.map { "\($0)°" } ?? "--", distance: 3 * u, tracking: 0)
                        .font(.system(size: 5.6 * u, weight: .regular))
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 0.2 * u) {
                    Image(systemName: weather.symbol + ".fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 2.2 * u))
                    Text(weather.condition)
                        .font(.system(size: 1.5 * u, weight: .semibold))
                    if let high = weather.high, let low = weather.low {
                        Text("H:\(high)° L:\(low)°").font(.system(size: 1.5 * u, weight: .medium))
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                ForEach(Array(weather.hours.enumerated()), id: \.element.id) { i, hour in
                    VStack(spacing: 0.5 * u) {
                        Text(i == 0 ? "Now" : hour.time.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated))))
                            .font(.system(size: 1.3 * u, weight: .semibold))
                            .opacity(0.8)
                        Image(systemName: hour.symbol + ".fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 1.8 * u))
                            .frame(height: 2.2 * u)
                        RollingText(text: "\(hour.temperature)°", distance: 1 * u, tracking: 0)
                            .font(.system(size: 1.5 * u, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .monospacedDigit()
        .padding(1.8 * u)
        .frame(width: grid.wide, height: grid.s)
        .glass(grid)
    }
}

// MARK: - Reminders

/// The incomplete reminders in the default Reminders list.
@MainActor
final class ReminderStore: ObservableObject {
    struct Item: Identifiable, Equatable {
        let id: String
        let title: String
        let due: Date?
    }

    @Published private(set) var listName = "Reminders"
    @Published private(set) var items: [Item] = []
    private let store = EKEventStore()

    var overdue: Int { items.filter { ($0.due ?? .distantFuture) < .now }.count }

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToReminders()
            refresh()
        }
    }

    func refresh() {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess,
              let list = store.defaultCalendarForNewReminders() else { return }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: [list])
        let name = list.title
        store.fetchReminders(matching: predicate) { reminders in
            let items = (reminders ?? [])
                .map { Item(id: $0.calendarItemIdentifier, title: $0.title ?? "", due: $0.dueDateComponents?.date) }
                .sorted { ($0.due ?? .distantFuture) < ($1.due ?? .distantFuture) }
            Task { @MainActor in
                self.listName = name
                if items != self.items { Motion.animate { self.items = items } }
            }
        }
    }

    /// Ticks a reminder off, as clicking its circle does in the Reminders widget.
    func complete(_ item: Item) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        try? store.save(reminder, commit: true)
        Motion.animate { items.removeAll { $0.id == item.id } }
    }
}

/// Like the Reminders widget, in white: list name and count, then the first few items with
/// circles you can click to complete them.
struct RemindersCard: View {
    @ObservedObject var reminders: ReminderStore
    let grid: Grid

    var body: some View {
        Group {
            if reminders.items.isEmpty { allDone } else { list }
        }
        .frame(width: grid.wide, height: grid.s)
        .glass(grid)
        .animation(Motion.layout, value: reminders.items.isEmpty)
    }

    /// Nothing left: a centred tick, as the Reminders widget shows for an empty list.
    private var allDone: some View {
        let u = grid.u
        return VStack(spacing: 0.8 * u) {
            Image(systemName: "checkmark.circle").font(.system(size: 4.4 * u, weight: .light))
            Text("All done").font(.system(size: 2 * u, weight: .semibold))
            Text(reminders.listName).font(.system(size: 1.4 * u)).opacity(0.6)
        }
        .transition(.opacity)
    }

    private var list: some View {
        let u = grid.u
        return HStack(alignment: .top, spacing: 2 * u) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    Circle().fill(.white.opacity(0.2))
                    Image(systemName: "list.bullet").font(.system(size: 1.6 * u, weight: .bold))
                }
                .frame(width: 3.4 * u, height: 3.4 * u)
                Spacer(minLength: 0)
                RollingText(text: "\(reminders.items.count)", distance: 3 * u, tracking: 0)
                    .font(.system(size: 4.4 * u, weight: .bold, design: .rounded))
                Text(reminders.listName)
                    .font(.system(size: 1.6 * u, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(width: 10 * u, alignment: .leading)

            VStack(alignment: .leading, spacing: 1.1 * u) {
                ForEach(reminders.items.prefix(4)) { item in
                    HStack(alignment: .firstTextBaseline, spacing: 0.9 * u) {
                        Button { reminders.complete(item) } label: {
                            Circle()
                                .strokeBorder(.white.opacity(0.7), lineWidth: 0.18 * u)
                                .frame(width: 1.6 * u, height: 1.6 * u)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Complete \(item.title)")
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 0.25 * u }
                        VStack(alignment: .leading, spacing: 0) {
                            Text(item.title).font(.system(size: 1.6 * u)).lineLimit(1)
                            if let due = item.due {
                                Text(due, format: .relative(presentation: .named))
                                    .font(.system(size: 1.2 * u))
                                    .fontWeight(due < .now ? .semibold : .regular)
                                    .opacity(due < .now ? 0.9 : 0.55)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(1.8 * u)
        .transition(.opacity)
    }
}

// MARK: - World Clock

/// A city in the World Clock card, stored as "Name=Area/Zone".
struct WorldCity: Hashable {
    static let key = "worldClockCities"
    static let defaults = "Tbilisi=Asia/Tbilisi;Mumbai=Asia/Kolkata;Tokyo=Asia/Tokyo;New York=America/New_York"

    var name: String
    var zone: String

    static func load(_ raw: String) -> [WorldCity] {
        raw.split(separator: ";").compactMap { part in
            let bits = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard bits.count == 2, TimeZone(identifier: String(bits[1])) != nil else { return nil }
            return WorldCity(name: String(bits[0]), zone: String(bits[1]))
        }
    }

    static func save(_ cities: [WorldCity]) -> String {
        cities.map { $0.name.replacingOccurrences(of: ";", with: "").replacingOccurrences(of: "=", with: "") + "=" + $0.zone }
            .joined(separator: ";")
    }
}

/// Like the Clock app's World Clock widget: four analog faces, white by day and black by night, with the
/// city and its offset from here below each.
struct WorldClockCard: View {
    let grid: Grid
    @AppStorage(WorldCity.key) private var raw = WorldCity.defaults

    var body: some View {
        let u = grid.u
        let cities = Array(WorldCity.load(raw).prefix(4))
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 0) {
                ForEach(cities, id: \.self) { city in
                    let zone = TimeZone(identifier: city.zone) ?? .current
                    VStack(spacing: 0.7 * u) {
                        AnalogFace(date: context.date, zone: zone, size: 8.4 * u)
                        VStack(spacing: 0.1 * u) {
                            Text(city.name).font(.system(size: 1.5 * u, weight: .semibold)).lineLimit(1)
                            Text(Self.offset(zone, at: context.date))
                                .font(.system(size: 1.2 * u))
                                .opacity(0.6)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 1.2 * u)
        .frame(width: grid.wide, height: grid.s)
        .glass(grid)
    }

    /// "Today, +0HRS", "Yesterday, −5:30", as the Clock widget writes it.
    static func offset(_ zone: TimeZone, at date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let here = Calendar.current
        let a = here.dateComponents([.year, .month, .day], from: date)
        let b = there.dateComponents([.year, .month, .day], from: date)
        let day = a == b ? "Today" : (b.day! > a.day! || b.month! > a.month! || b.year! > a.year! ? "Tomorrow" : "Yesterday")
        let h = abs(seconds) / 3600, m = abs(seconds) % 3600 / 60
        let sign = seconds < 0 ? "−" : "+"
        return m == 0 ? "\(day), \(sign)\(h)HRS" : "\(day), \(sign)\(h):\(String(format: "%02d", m))"
    }
}

/// A Clock-app style face in black and white: 12 numerals, hour and minute hands, a grey second hand.
struct AnalogFace: View {
    let date: Date
    let zone: TimeZone
    let size: CGFloat

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hour = Double(c.hour ?? 0), minute = Double(c.minute ?? 0), second = Double(c.second ?? 0)
        let day = (6..<18).contains(c.hour ?? 0)
        let ink: Color = day ? .black : .white
        return ZStack {
            Circle().fill(day ? Color.white : Color.black)
            Circle().strokeBorder(.white.opacity(day ? 0 : 0.15), lineWidth: 1)
            ForEach(1...12, id: \.self) { n in
                let a = Double(n) / 12 * 2 * .pi
                Text("\(n)")
                    .font(.system(size: size * 0.13, weight: .medium, design: .rounded))
                    .foregroundStyle(ink)
                    .offset(x: sin(a) * size * 0.38, y: -cos(a) * size * 0.38)
            }
            hand(angle: (hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12, length: 0.25, width: 0.045, color: ink)
            hand(angle: (minute + second / 60) / 60, length: 0.38, width: 0.035, color: ink)
            hand(angle: second / 60, length: 0.42, width: 0.012, color: Color(white: 0.5))
            Circle().fill(Color(white: 0.5)).frame(width: size * 0.05)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
    }

    private func hand(angle: Double, length: CGFloat, width: CGFloat, color: Color) -> some View {
        Capsule()
            .fill(color)
            .frame(width: size * width, height: size * length)
            .offset(y: -size * length / 2)
            .rotationEffect(.radians(angle * 2 * .pi))
    }
}

// MARK: - Focus timer

/// A countdown that keeps running while standby is closed. Click to start or pause.
@MainActor
final class FocusTimer: ObservableObject {
    static let minutesKey = "timerMinutes"

    @Published private(set) var endsAt: Date?
    @Published private(set) var pausedLeft: TimeInterval?
    @Published private(set) var finished = false
    private var alarm: Timer?

    var length: TimeInterval {
        let m = UserDefaults.standard.integer(forKey: Self.minutesKey)
        return TimeInterval(m > 0 ? m : 25) * 60
    }

    var running: Bool { endsAt != nil }

    func left(at date: Date) -> TimeInterval {
        if let endsAt { return max(0, endsAt.timeIntervalSince(date)) }
        return pausedLeft ?? length
    }

    func toggle() {
        if let endsAt {
            pausedLeft = max(0, endsAt.timeIntervalSinceNow)
            self.endsAt = nil
            alarm?.invalidate()
        } else {
            finished = false
            let left = pausedLeft ?? length
            pausedLeft = nil
            endsAt = .now + left
            alarm = Timer.scheduledTimer(withTimeInterval: left, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish() }
            }
        }
    }

    func reset() {
        alarm?.invalidate()
        endsAt = nil
        pausedLeft = nil
        finished = false
    }

    private func finish() {
        endsAt = nil
        pausedLeft = nil
        finished = true
        NSSound(named: "Glass")?.play()
    }
}

/// Like the Clock app's Timer widget, in white: a ring that empties, the time left in the middle.
struct TimerCard: View {
    @ObservedObject var timer: FocusTimer
    let grid: Grid

    var body: some View {
        let u = grid.u
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = timer.left(at: context.date)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(timer.finished ? "Done" : "Focus").font(.system(size: 1.5 * u, weight: .semibold))
                    Spacer()
                    Image(systemName: timer.running ? "pause.fill" : "play.fill")
                        .font(.system(size: 1.3 * u))
                }
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 0.9 * u)
                    Circle()
                        .trim(from: 0, to: left / timer.length)
                        .stroke(.white, style: StrokeStyle(lineWidth: 0.9 * u, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                    RollingText(text: Duration.seconds(left.rounded(.up)).formatted(.time(pattern: left >= 3600 ? .hourMinuteSecond : .minuteSecond)),
                                distance: 1.4 * u, tracking: 0)
                        .font(.system(size: 2.4 * u, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 12 * u, height: 12 * u)
                .frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        }
        .padding(1.8 * u)
        .frame(width: grid.cw, height: grid.s)
        .glass(grid)
        .overlay {
            // When time is up: a slow white pulse around the card, for when the sound is off.
            if timer.finished {
                RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
                    .strokeBorder(.white, lineWidth: 0.35 * u)
                    .shadow(color: .white.opacity(0.8), radius: 1.5 * u)
                    .phaseAnimator([0.15, 0.9]) { view, phase in view.opacity(phase) } animation: { _ in .easeInOut(duration: 1.4) }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.6), value: timer.finished)
        .contentShape(Rectangle())
        .onTapGesture { timer.toggle() }
        .contextMenu { Button("Reset Timer") { timer.reset() } }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(timer.running ? "Pause focus timer" : "Start focus timer")
    }
}

// MARK: - Hover details

/// Shows one extra line at the bottom of a card while the pointer is over it.
struct HoverDetail: ViewModifier {
    let text: String?
    let grid: Grid
    @StateObject private var hover = HoverState()

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if hover.on, let text {
                    Text(text)
                        .font(.system(size: 1.3 * grid.u, weight: .medium))
                        .lineLimit(1)
                        .padding(.horizontal, 1.2 * grid.u)
                        .padding(.vertical, 0.6 * grid.u)
                        .glass(grid, capsule: true)
                        .padding(.bottom, 0.8 * grid.u)
                        .transition(.opacity.combined(with: .offset(y: 0.6 * grid.u)))
                        .allowsHitTesting(false)
                }
            }
            .onHover { on in withAnimation(.smooth(duration: 0.25)) { hover.on = on } }
    }
}

extension View {
    func hoverDetail(_ text: String?, grid: Grid) -> some View { modifier(HoverDetail(text: text, grid: grid)) }
}

// MARK: - Rolling digits

/// The clock's digits roll up when they change, each one on its own, like a mechanical counter.
struct RollingText: View {
    let text: String
    let distance: CGFloat
    let tracking: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: tracking) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                ZStack {
                    Text(String(ch))
                        .id(ch)
                        .transition(reduceMotion ? .opacity : .roll(distance))
                }
            }
        }
        .animation(.spring(duration: 0.7, bounce: 0.2), value: text)
    }
}

private struct Roll: ViewModifier {
    let y: CGFloat
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View { content.offset(y: y).opacity(opacity).blur(radius: blur) }
}

extension AnyTransition {
    /// In from below, out through the top, blurred while moving.
    static func roll(_ d: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(active: Roll(y: d, opacity: 0, blur: d * 0.12), identity: Roll(y: 0, opacity: 1, blur: 0)),
            removal: .modifier(active: Roll(y: -d, opacity: 0, blur: d * 0.12), identity: Roll(y: 0, opacity: 1, blur: 0))
        )
    }
}

// MARK: - Night mode

/// When night mode is on: off, on a schedule, or always.
enum NightMode: String, CaseIterable {
    static let key = "nightMode"
    static let startKey = "nightStart"   // hour, 0–23
    static let endKey = "nightEnd"       // hour, 0–23
    static let tintKey = "nightTint"
    case off, scheduled, always

    /// Whether night mode applies at this moment.
    static func isOn(at date: Date = .now) -> Bool {
        let d = UserDefaults.standard
        switch NightMode(rawValue: d.string(forKey: key) ?? "") ?? .off {
        case .off: return false
        case .always: return true
        case .scheduled:
            let start = d.object(forKey: startKey) as? Int ?? 22
            let end = d.object(forKey: endKey) as? Int ?? 7
            let hour = Calendar.current.component(.hour, from: date)
            return start <= end ? (start..<end).contains(hour) : hour >= start || hour < end
        }
    }
}

enum NightTint: String, CaseIterable {
    case red, grey

    var color: Color {
        switch self {
        case .red: Color(red: 1, green: 0.2, blue: 0.15)
        case .grey: Color(white: 0.75)
        }
    }
}

/// Re-checks night mode every minute, so the overlay changes over at the scheduled hour.
@MainActor
final class NightMonitor: ObservableObject {
    @Published private(set) var on = NightMode.isOn()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func check() {
        let now = NightMode.isOn()
        if now != on { withAnimation(.easeInOut(duration: 1.5)) { on = now } }
    }
}

// MARK: - Clock colour

/// The clock's colour: white, the colour of the music playing, or one you pick.
enum ClockColor: String, CaseIterable {
    static let key = "clockColor"
    static let customKey = "clockCustomColor" // "r,g,b", 0–1
    case white, music, custom

    var name: String {
        switch self {
        case .white: "White"
        case .music: "Match Music"
        case .custom: "Custom"
        }
    }

    static func custom(from raw: String) -> Color {
        let v = raw.split(separator: ",").compactMap { Double($0) }
        return v.count == 3 ? Color(red: v[0], green: v[1], blue: v[2]) : Color(red: 1, green: 0.62, blue: 0.04)
    }

    static func raw(from color: Color) -> String {
        let c = NSColor(color).usingColorSpace(.sRGB) ?? .orange
        return String(format: "%.3f,%.3f,%.3f", c.redComponent, c.greenComponent, c.blueComponent)
    }
}

extension Palette {
    /// The brightest album colour, lifted toward white so it reads as text on glass.
    var accent: Color {
        let c = colors.max { $0.luminance < $1.luminance } ?? base
        let lift = max(0, 0.75 - c.luminance) * 0.8
        return Color(red: c.r + (1 - c.r) * lift, green: c.g + (1 - c.g) * lift, blue: c.b + (1 - c.b) * lift)
    }
}
