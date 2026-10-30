import AppKit
import EventKit
import SwiftUI

// Cards modelled on the macOS desktop widgets: Weather (medium), Reminders (medium),
// World Clock (medium, four faces) and a Timer (small).

// MARK: - Weather

/// Like the Weather widget: place, temperature, condition, high and low, then the next hours or days,
/// in white on glass like every other card.
struct WeatherCard: View {
    @ObservedObject var weather: WeatherStore
    let grid: Grid
    var size: WidgetSize = .medium
    var style = 0

    var body: some View {
        content
            .monospacedDigit()
            .padding(1.8 * grid.u)
            .frame(width: grid.w(size), height: grid.h(size), alignment: .topLeading)
            .glass(grid)
    }

    private var temperature: String { weather.temperature.map { "\($0)°" } ?? "--" }
    private var highLow: String? { weather.high.flatMap { h in weather.low.map { "H:\(h)° L:\($0)°" } } }

    @ViewBuilder private var content: some View {
        let u = grid.u
        switch (size, style) {
        case (.small, 1):
            VStack(spacing: 0.4 * u) {
                Image(systemName: weather.symbol + ".fill").symbolRenderingMode(.hierarchical).font(.system(size: 6.4 * u))
                    .frame(height: 8 * u)
                RollingText(text: temperature, distance: 2 * u, tracking: 0).font(.system(size: 3 * u, weight: .medium))
                Text(weather.city ?? "My Location").font(.system(size: 1.4 * u)).opacity(0.6).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case (.small, _):
            VStack(alignment: .leading, spacing: 0) {
                place
                RollingText(text: temperature, distance: 3 * u, tracking: 0).font(.system(size: 5.2 * u))
                Spacer(minLength: 0)
                Image(systemName: weather.symbol + ".fill").symbolRenderingMode(.hierarchical).font(.system(size: 1.8 * u))
                Text(weather.condition).font(.system(size: 1.4 * u, weight: .semibold)).lineLimit(1)
                if let highLow { Text(highLow).font(.system(size: 1.4 * u, weight: .medium)).opacity(0.7) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case (.medium, 1) where !weather.days.isEmpty:
            HStack(spacing: 0) {
                ForEach(weather.days.prefix(5)) { day in
                    VStack(spacing: 0.8 * u) {
                        Text(Calendar.current.isDateInToday(day.date) ? "Today" : day.date.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.system(size: 1.4 * u, weight: .semibold)).opacity(0.7)
                        Image(systemName: day.symbol + ".fill").symbolRenderingMode(.hierarchical).font(.system(size: 2.4 * u))
                            .frame(height: 3 * u)
                        Text("\(day.high)°").font(.system(size: 1.8 * u, weight: .semibold))
                        Text("\(day.low)°").font(.system(size: 1.5 * u)).opacity(0.6)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        case (.medium, _):
            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                hours
            }
        case (.large, 1):
            VStack(alignment: .leading, spacing: 0) {
                place
                RollingText(text: temperature, distance: 3 * u, tracking: 0).font(.system(size: 8 * u, weight: .thin))
                Text([weather.condition, highLow].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 1.6 * u)).opacity(0.7)
                Spacer(minLength: 0)
                hours.padding(.bottom, 1.4 * u)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 1 * u), GridItem(.flexible())], spacing: 1 * u) {
                    tile("FEELS LIKE", weather.feelsLike.map { "\($0)°" })
                    tile("HUMIDITY", weather.humidity.map { "\($0)%" })
                    tile("WIND", weather.wind.map { "\($0) \(Locale.current.measurementSystem == .us ? "mph" : "km/h")" })
                    tile("TOMORROW", weather.days.dropFirst().first.map { "\($0.high)° / \($0.low)°" })
                }
            }
        case (.large, _):
            VStack(spacing: 0) {
                header
                hours.padding(.vertical, 1.4 * u)
                Divider().overlay(.white.opacity(0.2))
                days(Array(weather.days.dropFirst().prefix(4)))
                    .padding(.top, 1 * u)
                Spacer(minLength: 0)
            }
        default:
            header
        }
    }

    private var place: some View {
        HStack(spacing: 0.4 * grid.u) {
            Text(weather.city ?? "My Location").lineLimit(1)
            Image(systemName: "location.fill").font(.system(size: 1.1 * grid.u))
        }
        .font(.system(size: 1.8 * grid.u, weight: .semibold))
    }

    private var header: some View {
        let u = grid.u
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                place
                RollingText(text: temperature, distance: 3 * u, tracking: 0).font(.system(size: 5.6 * u, weight: .regular))
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 0.2 * u) {
                Image(systemName: weather.symbol + ".fill").symbolRenderingMode(.hierarchical).font(.system(size: 2.2 * u))
                Text(weather.condition).font(.system(size: 1.5 * u, weight: .semibold))
                if let highLow { Text(highLow).font(.system(size: 1.5 * u, weight: .medium)) }
            }
        }
    }

    private var hours: some View {
        let u = grid.u
        return HStack(spacing: 0) {
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

    /// One row per day with a bar showing its range within the week's lowest and highest.
    private func days(_ list: [WeatherStore.Day]) -> some View {
        let u = grid.u
        let lo = Double(weather.days.map(\.low).min() ?? 0), hi = Double(weather.days.map(\.high).max() ?? 1)
        let span = max(1, hi - lo)
        return VStack(spacing: 1 * u) {
            ForEach(list) { day in
                HStack(spacing: 1.2 * u) {
                    Text(day.date.formatted(.dateTime.weekday(.abbreviated))).frame(width: 4.5 * u, alignment: .leading)
                    Image(systemName: day.symbol + ".fill").symbolRenderingMode(.hierarchical).frame(width: 2.6 * u)
                    Text("\(day.low)°").opacity(0.6).frame(width: 3.2 * u, alignment: .trailing)
                    Bar(fraction: (Double(day.high) - lo) / span, height: 0.45 * u, from: (Double(day.low) - lo) / span)
                    Text("\(day.high)°").frame(width: 3.2 * u, alignment: .trailing)
                }
                .font(.system(size: 1.6 * u, weight: .medium))
            }
        }
    }

    private func tile(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 0.3 * grid.u) {
            Text(label).font(.system(size: 1.1 * grid.u, weight: .semibold)).tracking(0.08 * grid.u).opacity(0.55)
            Text(value ?? "--").font(.system(size: 2 * grid.u, weight: .medium)).lineLimit(1)
        }
        .padding(1 * grid.u)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 1.4 * grid.u, style: .continuous).fill(.white.opacity(0.08)))
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

    /// Debug: a few reminders, for the card renderer.
    func preview() {
        let cal = Calendar.current
        let d = { (days: Int) in cal.date(byAdding: .day, value: days, to: .now) }
        items = [("Groceries", d(0)), ("Call bank", d(0)), ("Pay rent", d(1)), ("Book flight", d(4)),
                 ("Renew ID", nil), ("Water plants", nil), ("Return library books", d(6))]
            .enumerated().map { Item(id: "\($0.offset)", title: $0.element.0, due: $0.element.1) }
    }

    /// Ticks a reminder off, as clicking its circle does in the Reminders widget.
    func complete(_ item: Item) {
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        do { try store.save(reminder, commit: true) } catch { return } // keep the item if the save failed
        Motion.animate { items.removeAll { $0.id == item.id } }
    }
}

/// Like the Reminders widget, in white: list name and count, then items with circles you can click to
/// complete them.
struct RemindersCard: View {
    @ObservedObject var reminders: ReminderStore
    let grid: Grid
    var size: WidgetSize = .medium
    var style = 0

    var body: some View {
        Group {
            if reminders.items.isEmpty { allDone } else { list.padding(1.8 * grid.u).transition(.opacity) }
        }
        .frame(width: grid.w(size), height: grid.h(size), alignment: .topLeading)
        .glass(grid)
        .animation(Motion.layout, value: reminders.items.isEmpty)
    }

    /// Nothing left: a centred tick, as the Reminders widget shows for an empty list.
    private var allDone: some View {
        let u = grid.u
        return VStack(spacing: 0.8 * u) {
            Image(systemName: "checkmark.circle").font(.system(size: (size == .small ? 3.4 : 4.4) * u, weight: .light))
            Text("All done").font(.system(size: 2 * u, weight: .semibold))
            Text(reminders.listName).font(.system(size: 1.4 * u)).opacity(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var chip: some View {
        ZStack {
            Circle().fill(.white.opacity(0.2))
            Image(systemName: "list.bullet").font(.system(size: 1.6 * grid.u, weight: .bold))
        }
        .frame(width: 3.4 * grid.u, height: 3.4 * grid.u)
    }

    private func count(_ points: CGFloat, weight: Font.Weight = .bold) -> some View {
        RollingText(text: "\(reminders.items.count)", distance: 3 * grid.u, tracking: 0)
            .font(.system(size: points * grid.u, weight: weight, design: .rounded))
    }

    @ViewBuilder private var list: some View {
        let u = grid.u
        switch (size, style) {
        case (.small, 1):
            VStack(alignment: .leading, spacing: 0) {
                chip
                Spacer(minLength: 0)
                count(7, weight: .light)
                Text(reminders.listName).font(.system(size: 1.6 * u, weight: .semibold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case (.small, _):
            VStack(alignment: .leading, spacing: 0) {
                HStack { chip; Spacer(); count(3.4) }
                Spacer(minLength: 0)
                items(4, dates: false)
            }
        case (.medium, 1):
            VStack(alignment: .leading, spacing: 1.4 * u) {
                HStack {
                    Text(reminders.listName).font(.system(size: 2 * u, weight: .semibold)).lineLimit(1)
                    Spacer()
                    count(3.2)
                }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 1.6 * u), GridItem(.flexible())], alignment: .leading, spacing: 1.1 * u) {
                let shown = reminders.items.count > 6 ? 5 : 6
                ForEach(reminders.items.prefix(shown)) { row($0, dates: false) }
                if reminders.items.count > 6 { more }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            }
        case (.medium, _):
            HStack(alignment: .top, spacing: 2 * u) {
                VStack(alignment: .leading, spacing: 0) {
                    chip
                    Spacer(minLength: 0)
                    count(4.4)
                    Text(reminders.listName).font(.system(size: 1.6 * u, weight: .semibold)).lineLimit(1)
                }
                .frame(width: 10 * u, alignment: .leading)
                items(4, dates: true)
            }
        case (.large, 1):
            grouped
        default:
            VStack(alignment: .leading, spacing: 1.6 * u) {
                HStack {
                    Text(reminders.listName).font(.system(size: 2 * u, weight: .semibold)).lineLimit(1)
                    Spacer()
                    count(3.2)
                }
                items(9, dates: true)
            }
        }
    }

    private var more: some View {
        Text("…").font(.system(size: 1.6 * grid.u)).opacity(0.7).padding(.leading, 0.2 * grid.u)
    }

    /// Up to n rows; when there are more than n, the last row becomes "…".
    private func items(_ n: Int, dates: Bool) -> some View {
        let over = reminders.items.count > n
        return VStack(alignment: .leading, spacing: 1.1 * grid.u) {
            ForEach(reminders.items.prefix(over ? n - 1 : n)) { row($0, dates: dates) }
            if over { more }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Overdue and today, tomorrow, then later (and undated).
    private var grouped: some View {
        let cal = Calendar.current
        let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now))!
        let dayAfter = cal.date(byAdding: .day, value: 1, to: startOfTomorrow)!
        let groups: [(String, [ReminderStore.Item])] = [
            ("TODAY", reminders.items.filter { ($0.due ?? .distantFuture) < startOfTomorrow }),
            ("TOMORROW", reminders.items.filter { (startOfTomorrow..<dayAfter).contains($0.due ?? .distantFuture) }),
            ("LATER", reminders.items.filter { ($0.due ?? .distantFuture) >= dayAfter }),
        ].filter { !$0.1.isEmpty }
        var left = 8
        let shown = groups.compactMap { name, list -> (String, [ReminderStore.Item])? in
            guard left > 0 else { return nil }
            let part = Array(list.prefix(left))
            left -= part.count
            return (name, part)
        }
        return VStack(alignment: .leading, spacing: 0.9 * grid.u) {
            ForEach(shown, id: \.0) { name, list in
                Text(name).font(.system(size: 1.2 * grid.u, weight: .bold)).tracking(0.08 * grid.u).opacity(0.55)
                    .padding(.top, name == shown.first?.0 ? 0 : 0.6 * grid.u)
                ForEach(list) { row($0, dates: false) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func row(_ item: ReminderStore.Item, dates: Bool) -> some View {
        let u = grid.u
        return HStack(alignment: .firstTextBaseline, spacing: 0.9 * u) {
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
                if dates, let due = item.due {
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

/// Like the Clock app's World Clock widget: analog faces or digital times, with each city's offset
/// from here.
struct WorldClockCard: View {
    let grid: Grid
    var size: WidgetSize = .medium
    var style = 0
    @AppStorage(WorldCity.key) private var raw = WorldCity.defaults

    var body: some View {
        let cities = Array(WorldCity.load(raw).prefix(size == .small ? (style == 1 ? 3 : 1) : 4))
        TimelineView(.everyMinute) { content(cities, $0.date) }
        .padding(1.6 * grid.u)
        .frame(width: grid.w(size), height: grid.h(size))
        .glass(grid)
    }

    @ViewBuilder private func content(_ cities: [WorldCity], _ date: Date) -> some View {
        let u = grid.u
        switch (size, style) {
        case (.small, 1), (.medium, 1):
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2.4 * u), count: size == .small ? 1 : 2),
                      spacing: (size == .small ? 1.2 : 1.6) * u) {
                ForEach(cities, id: \.self) { city in
                    let zone = TimeZone(identifier: city.zone) ?? .current
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(city.name).font(.system(size: 1.5 * u, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 0.4 * u)
                            Text(Self.time(date, zone)).font(.system(size: (size == .small ? 2 : 2.6) * u, weight: .medium)).monospacedDigit()
                        }
                        if size != .small {
                            Text(Self.offsetLines(zone, at: date)).font(.system(size: 1.1 * u)).opacity(0.6).lineLimit(2)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        case (.small, _):
            let city = cities.first ?? WorldCity(name: "Here", zone: TimeZone.current.identifier)
            VStack(spacing: 0.7 * u) {
                AnalogFace(date: date, zone: TimeZone(identifier: city.zone) ?? .current, size: 12 * u)
                Text(city.name).font(.system(size: 1.5 * u, weight: .semibold)).lineLimit(1)
            }
        case (.large, 1):
            VStack(spacing: 0) {
                ForEach(Array(cities.enumerated()), id: \.element) { i, city in
                    let zone = TimeZone(identifier: city.zone) ?? .current
                    if i > 0 { Divider().overlay(.white.opacity(0.15)) }
                    HStack {
                        VStack(alignment: .leading, spacing: 0.2 * u) {
                            Text(city.name).font(.system(size: 1.8 * u, weight: .semibold)).lineLimit(1)
                            Text(Self.offset(zone, at: date)).font(.system(size: 1.2 * u)).opacity(0.6).lineLimit(1)
                        }
                        Spacer()
                        Text(Self.time(date, zone)).font(.system(size: 5 * u, weight: .medium)).monospacedDigit()
                    }
                    .frame(maxHeight: .infinity)
                }
            }
        case (.large, _):
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 1.6 * u) {
                ForEach(cities, id: \.self) { city in
                    let zone = TimeZone(identifier: city.zone) ?? .current
                    VStack(spacing: 0.6 * u) {
                        AnalogFace(date: date, zone: zone, size: 12.5 * u)
                        Text(city.name).font(.system(size: 1.6 * u, weight: .semibold)).lineLimit(1)
                        Text(Self.time(date, zone)).font(.system(size: 1.4 * u)).monospacedDigit().opacity(0.8)
                    }
                }
            }
        default:
            HStack(spacing: 0) {
                ForEach(cities, id: \.self) { city in
                    let zone = TimeZone(identifier: city.zone) ?? .current
                    VStack(spacing: 0.7 * u) {
                        AnalogFace(date: date, zone: zone, size: 8.4 * u)
                        VStack(spacing: 0.1 * u) {
                            Text(city.name).font(.system(size: 1.5 * u, weight: .semibold)).lineLimit(1)
                            Text(Self.offsetLines(zone, at: date)).font(.system(size: 1.2 * u)).opacity(0.6).lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    /// "23:11" in that city.
    static func time(_ date: Date, _ zone: TimeZone) -> String {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()
        style.timeZone = zone
        return date.formatted(style)
    }

    /// Today / Tomorrow / Yesterday, comparing (year, month, day) in order so month and year ends work.
    static func dayLabel(here a: (Int, Int, Int), there b: (Int, Int, Int)) -> String {
        a == b ? "Today" : (b > a ? "Tomorrow" : "Yesterday")
    }

    /// "Today, +0HRS", "Yesterday, −5:30", as the Clock widget writes it.
    static func offset(_ zone: TimeZone, at date: Date) -> String {
        let p = offsetParts(zone, at: date)
        return "\(p.day), \(p.amount)"
    }

    /// The same text split in two ("Yesterday" / "−5:30") for narrow cards, where one line truncates.
    static func offsetLines(_ zone: TimeZone, at date: Date) -> String {
        let p = offsetParts(zone, at: date)
        return "\(p.day)\n\(p.amount)"
    }

    static func offsetParts(_ zone: TimeZone, at date: Date) -> (day: String, amount: String) {
        let seconds = zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        let here = Calendar.current
        let a = here.dateComponents([.year, .month, .day], from: date)
        let b = there.dateComponents([.year, .month, .day], from: date)
        let day = dayLabel(here: (a.year!, a.month!, a.day!), there: (b.year!, b.month!, b.day!))
        let h = abs(seconds) / 3600, m = abs(seconds) % 3600 / 60
        let sign = seconds < 0 ? "−" : "+"
        return (day, m == 0 ? "\(sign)\(h)HRS" : "\(sign)\(h):\(String(format: "%02d", m))")
    }
}

/// A Clock-app style face, see-through: 12, 3, 6, 9 and two hands that stop short of them (no second
/// hand, so it only needs a redraw each minute). Daytime cities get a faint glass fill so day and night
/// still read apart.
struct AnalogFace: View {
    let date: Date
    let zone: TimeZone
    let size: CGFloat

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let hour = Double(c.hour ?? 0), minute = Double(c.minute ?? 0)
        let day = (6..<18).contains(c.hour ?? 0)
        return ZStack {
            Circle().fill(.white.opacity(day ? 0.1 : 0))
            Circle().strokeBorder(.white.opacity(day ? 0.3 : 0.2), lineWidth: max(1, size * 0.01))
            ForEach([12, 3, 6, 9], id: \.self) { n in
                let a = Double(n) / 12 * 2 * .pi
                Text("\(n)")
                    .font(.system(size: size * 0.15, weight: .medium))
                    .offset(x: sin(a) * size * 0.405, y: -cos(a) * size * 0.405)
            }
            hand(angle: (hour.truncatingRemainder(dividingBy: 12) + minute / 60) / 12, length: 0.25, width: 0.045)
            hand(angle: minute / 60, length: 0.32, width: 0.035)
            Circle().fill(.white).frame(width: size * 0.05)
        }
        .foregroundStyle(.white)
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
    }

    private func hand(angle: Double, length: CGFloat, width: CGFloat) -> some View {
        Capsule()
            .fill(.white)
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

/// Like the Clock app's Timer widget, in white: a ring that empties or big digits, the time left.
/// Click to start or pause.
struct TimerCard: View {
    @ObservedObject var timer: FocusTimer
    let grid: Grid
    var size: WidgetSize = .small
    var style = 0
    @AppStorage(FocusTimer.minutesKey) private var minutes = 25

    var body: some View {
        let u = grid.u
        // No per-second ticks while paused or finished.
        Group {
            if timer.running {
                TimelineView(.periodic(from: .now, by: 1)) { content(timer.left(at: $0.date), $0.date) }
            } else {
                TimelineView(.explicit([.now])) { content(timer.left(at: $0.date), $0.date) }
            }
        }
        .padding(1.8 * u)
        .frame(width: grid.w(size), height: grid.h(size))
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

    private func text(_ left: TimeInterval) -> String {
        Duration.seconds(left.rounded(.up)).formatted(.time(pattern: left >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    private var title: some View {
        Text(timer.finished ? "Done" : "Focus").font(.system(size: 1.5 * grid.u, weight: .semibold))
    }

    private var playPause: some View {
        Image(systemName: timer.running ? "pause.fill" : "play.fill").font(.system(size: 1.3 * grid.u))
    }

    /// "ends 11:26" while running.
    @ViewBuilder private func ends(_ left: TimeInterval, _ now: Date) -> some View {
        if timer.running {
            Text("ends " + (now + left).formatted(date: .omitted, time: .shortened))
                .font(.system(size: 1.3 * grid.u)).opacity(0.6)
        }
    }

    private func ring(_ left: TimeInterval, side: CGFloat, font: CGFloat) -> some View {
        let u = grid.u
        return ZStack {
            Circle().stroke(.white.opacity(0.2), lineWidth: 0.9 * u)
            Circle()
                .trim(from: 0, to: left / timer.length)
                .stroke(.white, style: StrokeStyle(lineWidth: 0.9 * u, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: left)
            RollingText(text: text(left), distance: 1.4 * u, tracking: 0)
                .font(.system(size: font * u, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: side * u, height: side * u)
    }

    @ViewBuilder private func content(_ left: TimeInterval, _ now: Date) -> some View {
        let u = grid.u
        switch (size, style) {
        case (.small, 1):
            let parts = text(left).split(separator: ":").map(String.init)
            VStack(alignment: .leading, spacing: 0) {
                HStack { title; Spacer(); playPause }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: -1 * u) {
                    ForEach(parts.suffix(2).indices, id: \.self) { i in
                        RollingText(text: parts.suffix(2)[i], distance: 2 * u, tracking: -0.2 * u)
                            .font(.system(size: 5.6 * u, weight: .medium))
                            .monospacedDigit()
                    }
                }
                Bar(fraction: left / timer.length, height: 0.45 * u).padding(.top, 1 * u)
            }
        case (.small, _):
            VStack(alignment: .leading, spacing: 0) {
                HStack { title; Spacer(); playPause }
                Spacer(minLength: 0)
                ring(left, side: 12, font: 2.4).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        case (_, 1):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0.8 * u) { title; Spacer(); ends(left, now); playPause }
                Spacer(minLength: 0)
                RollingText(text: text(left), distance: 3 * u, tracking: -0.3 * u)
                    .font(.system(size: 8.5 * u, weight: .medium))
                    .monospacedDigit()
                Bar(fraction: left / timer.length, height: 0.45 * u).padding(.top, 1 * u)
            }
        default:
            HStack(spacing: 2.6 * u) {
                ring(left, side: 12.5, font: 2.6)
                VStack(alignment: .leading, spacing: 1.2 * u) {
                    HStack(spacing: 0.8 * u) { title; playPause }
                    HStack(spacing: 0.6 * u) {
                        ForEach([15, 25, 45], id: \.self) { m in
                            Button { minutes = m; timer.reset() } label: {
                                Text("\(m)")
                                    .font(.system(size: 1.4 * u, weight: .semibold))
                                    .padding(.horizontal, 1 * u)
                                    .padding(.vertical, 0.5 * u)
                                    .background(Capsule().fill(.white.opacity(minutes == m ? 0.3 : 0.12)))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(m) minutes")
                        }
                    }
                    ends(left, now)
                }
                Spacer(minLength: 0)
            }
        }
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
    private var observer: NSObjectProtocol?

    /// Watches the schedule only while the overlay shows.
    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer?.tolerance = 5
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
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
