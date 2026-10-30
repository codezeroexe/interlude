import CoreLocation
import EventKit
import Foundation
import IOKit.ps

/// Battery level and whether the charger is connected.
@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level = 1.0
    @Published private(set) var pluggedIn = false
    /// Minutes to empty (on battery) or to full (charging), when macOS knows.
    @Published private(set) var minutesLeft: Int?
    /// Connected Bluetooth devices that report a battery level.
    @Published private(set) var devices: [Device] = []
    private var timer: Timer?
    private var lastDeviceCheck = Date.distantPast

    struct Device: Equatable, Identifiable {
        let name: String
        let level: Double
        let symbol: String
        var id: String { name }
    }

    /// Polls only while the overlay shows, so demo instances and a hidden overlay cost nothing.
    func start() {
        guard timer == nil else { return }
        // show() refreshes right before this.
        // ponytail: 30 s polling; switch to IOPSNotificationCreateRunLoopSource if it feels laggy.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 5
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Cheap plugged-in check for the idle monitor: no device scan, no system_profiler.
    nonisolated static var isPluggedIn: Bool {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        return IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? == kIOPSACPowerValue
    }

    func refresh() {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        guard let source = sources.first,
              let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else { return }
        let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
        // Publish only real changes, so the cards don't re-evaluate every 30 s for nothing.
        let newLevel = max > 0 ? Double(current) / Double(max) : 0
        if level != newLevel { level = newLevel }
        let newPlugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        if pluggedIn != newPlugged { pluggedIn = newPlugged }
        let minutes = desc[pluggedIn ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey] as? Int ?? -1
        let newMinutes = minutes > 0 ? minutes : nil
        if minutesLeft != newMinutes { minutesLeft = newMinutes }
        // ponytail: system_profiler is slow (about a second), so devices are checked every 2 min, off the main thread.
        if Date().timeIntervalSince(lastDeviceCheck) > 120 {
            lastDeviceCheck = Date()
            Task.detached(priority: .utility) {
                let found = Self.bluetoothDevices()
                await MainActor.run { if found != self.devices { Motion.animate { self.devices = found } } }
            }
        }
    }

    /// Battery levels of connected Bluetooth devices, from System Information. AirPods report each bud
    /// and the case; the card shows the lower bud.
    nonisolated static func bluetoothDevices() -> [Device] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.qualityOfService = .utility
        guard (try? process.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controller = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = controller["device_connected"] as? [[String: [String: Any]]]
        else { return [] }
        return connected.flatMap { $0 }.compactMap { name, info in
            let percent = { (key: String) in (info[key] as? String).flatMap { Double($0.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) } }
            let buds = [percent("device_batteryLevelLeft"), percent("device_batteryLevelRight")].compactMap { $0 }
            guard let level = buds.min() ?? percent("device_batteryLevelMain") ?? percent("device_batteryLevel") else { return nil }
            return Device(name: name, level: level / 100, symbol: symbol(name: name, type: info["device_minorType"] as? String ?? ""))
        }
        .sorted { $0.name < $1.name }
    }

    nonisolated private static func symbol(name: String, type: String) -> String {
        let n = name.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        switch type {
        case "Headphones", "Headset": return "headphones"
        case "Mouse": return "computermouse"
        case "Keyboard": return "keyboard"
        case "Trackpad": return "rectangle.and.hand.point.up.left"
        case "Speaker": return "hifispeaker"
        case "Gamepad", "GameController": return "gamecontroller"
        default: return "wave.3.right"
        }
    }

    /// For the hover detail: "3 h 12 min left", "Full in 45 min", or "Fully charged".
    var detail: String {
        let percent = "\(Int((level * 100).rounded()))%"
        if !devices.isEmpty {
            return (["Mac \(percent)"] + devices.map { "\($0.name) \(Int(($0.level * 100).rounded()))%" }).joined(separator: " · ")
        }
        guard let m = minutesLeft else { return pluggedIn && level >= 0.99 ? "Fully charged" : percent }
        let time = m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
        return pluggedIn ? "\(percent) · full in \(time)" : "\(percent) · \(time) left"
    }
}

/// Timed events for the next week, from Calendar.
@MainActor
final class CalendarStore: ObservableObject {
    struct Event: Equatable, Hashable, Identifiable {
        let title: String
        let start: Date
        var end: Date? = nil
        /// EventKit's identifier. The same meeting on two calendars is two events, so lists key on it.
        var uid: String? = nil
        var id: String { "\(uid ?? title)|\(start.timeIntervalSince1970)" }
    }

    /// The next timed event today.
    @Published private(set) var next: Event?
    /// Timed events from now until a week ahead, soonest first.
    @Published private(set) var upcoming: [Event] = []

    /// The rest of today's timed events.
    var today: [Event] { upcoming.filter { Calendar.current.isDateInToday($0.start) } }
    private let store = EKEventStore()

    func requestAccess() {
        Task {
            _ = try? await store.requestFullAccessToEvents()
            refresh()
        }
    }

    func refresh() {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return }
        let now = Date()
        let weekOut = Calendar.current.date(byAdding: .day, value: 7, to: Calendar.current.startOfDay(for: now))!
        let predicate = store.predicateForEvents(withStart: now, end: weekOut, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.startDate >= now }
            .sorted { $0.startDate < $1.startDate }
            .map { Event(title: $0.title ?? "Event", start: $0.startDate, end: $0.endDate, uid: $0.eventIdentifier) }
        let first = events.first { Calendar.current.isDateInToday($0.start) }
        if events != upcoming || first != next { Motion.animate { upcoming = events; next = first } }
    }
}

/// Month layout for the calendar card, weeks starting on Monday.
enum MonthGrid {
    /// Day numbers for the month containing `date`, with `nil` for the blank cells before day 1.
    static func days(for date: Date, calendar: Calendar = .current) -> [Int?] {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let count = calendar.range(of: .day, in: .month, for: start)!.count
        let weekday = calendar.component(.weekday, from: start) // 1 = Sunday
        let blanks = (weekday + 5) % 7
        return Array(repeating: nil, count: blanks) + (1...count).map { $0 }
    }
}

/// Weather for where the Mac is, from Open-Meteo (free, no key): now, today's high and low, and the
/// next hours. The place name comes from reverse geocoding.
@MainActor
final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Hour: Equatable, Identifiable {
        let time: Date
        let symbol: String
        let temperature: Int
        var id: Date { time }
    }

    struct Day: Equatable, Identifiable {
        let date: Date
        let symbol: String
        let high: Int
        let low: Int
        var id: Date { date }
    }

    @Published private(set) var temperature: Int?
    @Published private(set) var symbol = "cloud"
    @Published private(set) var code = 3
    @Published private(set) var isDay = true
    @Published private(set) var city: String?
    @Published private(set) var high: Int?
    @Published private(set) var low: Int?
    @Published private(set) var hours: [Hour] = []
    /// Today and the next five days.
    @Published private(set) var days: [Day] = []
    @Published private(set) var feelsLike: Int?
    @Published private(set) var wind: Int?
    @Published private(set) var humidity: Int?
    private let location = CLLocationManager()
    private var lastFetch = Date.distantPast

    override init() {
        super.init()
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    var condition: String { Self.condition(code: code) }

    func requestAccess() {
        location.requestWhenInUseAuthorization()
    }

    /// Fetches at most every 30 minutes; called each time the overlay opens.
    func refresh() {
        guard Date().timeIntervalSince(lastFetch) > 30 * 60 else { return }
        location.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let place = locations.last else { return }
        Task { @MainActor in
            await self.fetch(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
            if let name = try? await CLGeocoder().reverseGeocodeLocation(place).first?.locality, name != self.city {
                Motion.animate { self.city = name }
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No permission or no fix: the weather stays hidden.
    }

    private func fetch(latitude: Double, longitude: Double) async {
        let unit = Locale.current.measurementSystem == .us ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : ""
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(latitude)&longitude=\(longitude)"
            + "&current=temperature_2m,weather_code,is_day,apparent_temperature,wind_speed_10m,relative_humidity_2m"
            + "&hourly=temperature_2m,weather_code,is_day&daily=temperature_2m_max,temperature_2m_min,weather_code"
            + "&forecast_days=6&timezone=auto&timeformat=unixtime\(unit)")!
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let forecast = try? JSONDecoder().decode(Forecast.self, from: data)
        else { return }
        let c = forecast.current
        let now = Date()
        let h = forecast.hourly
        let upcoming = h.time.indices
            .filter { Date(timeIntervalSince1970: h.time[$0]) > now.addingTimeInterval(-3600) }
            .prefix(6)
            .map { i in
                Hour(time: Date(timeIntervalSince1970: h.time[i]),
                     symbol: Self.symbol(code: h.weather_code[i], isDay: h.is_day[i] == 1),
                     temperature: Int(h.temperature_2m[i].rounded()))
            }
        let d = forecast.daily
        let daily = d.time.indices.compactMap { i -> Day? in
            guard i < d.weather_code.count, i < d.temperature_2m_max.count, i < d.temperature_2m_min.count else { return nil }
            return Day(date: Date(timeIntervalSince1970: d.time[i]), symbol: Self.symbol(code: d.weather_code[i], isDay: true),
                       high: Int(d.temperature_2m_max[i].rounded()), low: Int(d.temperature_2m_min[i].rounded()))
        }
        Motion.animate {
            days = daily
            temperature = Int(c.temperature_2m.rounded())
            code = c.weather_code
            isDay = c.is_day == 1
            symbol = Self.symbol(code: c.weather_code, isDay: isDay)
            feelsLike = Int(c.apparent_temperature.rounded())
            wind = Int(c.wind_speed_10m.rounded())
            humidity = c.relative_humidity_2m
            high = forecast.daily.temperature_2m_max.first.map { Int($0.rounded()) }
            low = forecast.daily.temperature_2m_min.first.map { Int($0.rounded()) }
            hours = Array(upcoming)
        }
        lastFetch = Date()
    }

    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
            let is_day: Int
            let apparent_temperature: Double
            let wind_speed_10m: Double
            let relative_humidity_2m: Int
        }
        struct Hourly: Decodable {
            let time: [Double]
            let temperature_2m: [Double]
            let weather_code: [Int]
            let is_day: [Int]
        }
        struct Daily: Decodable {
            let time: [Double]
            let weather_code: [Int]
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    /// SF Symbol for a WMO weather code, as Open-Meteo reports it.
    nonisolated static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max" : "moon.stars"
        case 1, 2: isDay ? "cloud.sun" : "cloud.moon"
        case 45, 48: "cloud.fog"
        case 51...57: "cloud.drizzle"
        case 61...67, 80...82: "cloud.rain"
        case 71...77, 85, 86: "cloud.snow"
        case 95...99: "cloud.bolt.rain"
        default: "cloud"
        }
    }

    /// Words for a WMO weather code, in the Weather app's style.
    nonisolated static func condition(code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1: "Mostly Clear"
        case 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Foggy"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 80...82: "Showers"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorms"
        default: "Cloudy"
        }
    }
}

// MARK: - Sample data for the card renderer

extension BatteryMonitor {
    /// Debug: a Mac and three devices, for the card renderer.
    func preview() {
        level = 0.68
        devices = [Device(name: "AirPods Pro", level: 0.6, symbol: "airpodspro"),
                   Device(name: "Mouse", level: 0.35, symbol: "magicmouse"),
                   Device(name: "Keyboard", level: 0.8, symbol: "keyboard")]
    }
}

extension CalendarStore {
    /// Debug: a few events this week, for the card renderer.
    func preview() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today)!
        }
        upcoming = [
            Event(title: "Standup", start: at(0, 23, 0), end: at(0, 23, 15)),
            Event(title: "Design review", start: at(0, 23, 30), end: at(0, 23, 59)),
            Event(title: "1:1 with Asha", start: at(1, 10), end: at(1, 10, 30)),
            Event(title: "Gym", start: at(1, 19, 30)),
            Event(title: "Flight to Mumbai", start: at(3, 7, 40)),
        ]
        next = upcoming.first
    }
}

extension WeatherStore {
    /// Debug: a clear night in Pune, for the card renderer.
    func preview() {
        city = "Pune"
        temperature = 25
        code = 0
        isDay = false
        symbol = Self.symbol(code: 0, isDay: false)
        high = 31
        low = 22
        feelsLike = 27
        wind = 9
        humidity = 64
        let now = Date.now
        let codes = [0, 0, 1, 3, 3, 2]
        hours = (0..<6).map { i in
            Hour(time: now.addingTimeInterval(Double(i) * 3600), symbol: Self.symbol(code: codes[i], isDay: false), temperature: 25 - i / 2)
        }
        let dayCodes = [0, 0, 2, 61, 3, 1]
        days = (0..<6).map { i in
            Day(date: Calendar.current.date(byAdding: .day, value: i, to: now)!, symbol: Self.symbol(code: dayCodes[i], isDay: true),
                high: 31 - i % 3, low: 22 - i % 2)
        }
    }
}
