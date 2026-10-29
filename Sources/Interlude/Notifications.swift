import AppKit
import os
import SQLite3
import SwiftUI

/// Notifications still sitting in Notification Center, grouped by app.
/// Read straight from Notification Center's own database, which needs Full Disk Access.
/// The database format is private and undocumented, so a macOS update can change it.
@MainActor
final class NotificationStore: ObservableObject {
    struct AppGroup: Identifiable, Equatable {
        let bundleID: String
        let title: String // sender or title of the newest notification
        let count: Int
        let newest: Double // delivery time of the newest one, seconds since 2001
        var id: String { bundleID }
    }

    @Published private(set) var groups: [AppGroup] = []
    private var timer: Timer?
    private let queue = DispatchQueue(label: "Interlude.notifications")

    /// Known locations: macOS 15 and later, then older releases.
    nonisolated private static var databases: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [home + "/Library/Group Containers/group.com.apple.usernoted/db2/db"]
        if let dir = darwinUserDir() { paths.append(dir + "/com.apple.notificationcenter/db2/db") }
        return paths
    }

    /// True once Full Disk Access is granted (the database opens).
    nonisolated static var hasAccess: Bool {
        databases.contains { FileHandle(forReadingAtPath: $0) != nil }
    }

    nonisolated private static let dismissedKey = "dismissedNotifications" // [bundle ID: newest dismissed delivery time]
    nonisolated static let hiddenKey = "hiddenNotificationApps"           // bundle IDs never shown

    /// Hides this app's current notifications; newer ones bring the pill back.
    func dismiss(_ group: AppGroup) {
        var dismissed = UserDefaults.standard.dictionary(forKey: Self.dismissedKey) as? [String: Double] ?? [:]
        dismissed[group.bundleID] = group.newest
        UserDefaults.standard.set(dismissed, forKey: Self.dismissedKey)
        Motion.animate { groups.removeAll { $0.id == group.id } }
    }

    /// Never shows this app again (undo from the menu bar).
    func hideApp(_ group: AppGroup) {
        let hidden = (UserDefaults.standard.stringArray(forKey: Self.hiddenKey) ?? []) + [group.bundleID]
        UserDefaults.standard.set(hidden, forKey: Self.hiddenKey)
        Motion.animate { groups.removeAll { $0.id == group.id } }
    }

    func start() {
        Self.log.notice("start: hasAccess=\(Self.hasAccess) paths=\(Self.databases, privacy: .public)")
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        queue.async {
            let groups = Self.databases.lazy.compactMap(Self.read).first ?? []
            DispatchQueue.main.async { if groups != self.groups { Motion.animate { self.groups = groups } } }
        }
    }

    nonisolated private static let log = Logger(subsystem: "com.hari.Interlude", category: "notifications")

    /// Newest notifications from the last day, grouped by app, newest app first.
    nonisolated private static func read(path: String) -> [AppGroup]? {
        let readable = FileHandle(forReadingAtPath: path) != nil
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil)
        guard rc == SQLITE_OK else {
            log.notice("open failed \(path, privacy: .public) readable=\(readable) rc=\(rc)")
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        let sql = """
        SELECT app.identifier, record.data, record.delivered_date FROM record JOIN app ON app.app_id = record.app_id
        WHERE record.delivered_date > ? ORDER BY record.delivered_date DESC LIMIT 100
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            log.notice("query failed \(path, privacy: .public): \(String(cString: sqlite3_errmsg(db)), privacy: .public); schema: \(schema(db), privacy: .public)")
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date.now.addingTimeInterval(-24 * 3600).timeIntervalSinceReferenceDate)

        let dismissed = UserDefaults.standard.dictionary(forKey: dismissedKey) as? [String: Double] ?? [:]
        let hidden = Set(UserDefaults.standard.stringArray(forKey: hiddenKey) ?? [])
        var order: [String] = []
        var titles: [String: String] = [:]
        var newest: [String: Double] = [:]
        var counts: [String: Int] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = sqlite3_column_text(statement, 0).map({ String(cString: $0) }) else { continue }
            let delivered = sqlite3_column_double(statement, 2)
            let lower = id.lowercased()
            // Skip macOS's own alerts ("_system_center_:…"), Claude (it has its own pill),
            // apps you've hidden, and anything you already dismissed.
            if id.hasPrefix("_system_center_") || lower.contains("anthropic") || lower.contains("claude")
                || hidden.contains(id) || delivered <= dismissed[id] ?? 0 { continue }
            if counts[id] == nil {
                order.append(id)
                titles[id] = title(from: statement)
                newest[id] = delivered
            }
            counts[id, default: 0] += 1
        }
        if order.isEmpty { log.info("no recent notifications; \(schema(db), privacy: .public)") }
        return order.prefix(3).map {
            AppGroup(bundleID: $0, title: titles[$0] ?? "", count: counts[$0] ?? 1, newest: newest[$0] ?? 0)
        }
    }

    /// Tables, row counts and the newest delivery date, for diagnosing an empty result.
    nonisolated private static func schema(_ db: OpaquePointer?) -> String {
        var out: [String] = []
        var st: OpaquePointer?
        let q = "SELECT name, sql FROM sqlite_master WHERE type='table'"
        if sqlite3_prepare_v2(db, q, -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW {
                out.append(sqlite3_column_text(st, 1).map { String(cString: $0) } ?? "")
            }
        }
        sqlite3_finalize(st)
        let q2 = "SELECT count(*), max(delivered_date) FROM record"
        if sqlite3_prepare_v2(db, q2, -1, &st, nil) == SQLITE_OK, sqlite3_step(st) == SQLITE_ROW {
            out.append("records=\(sqlite3_column_int(st, 0)) newest=\(sqlite3_column_double(st, 1)) now=\(Date.now.timeIntervalSinceReferenceDate)")
        }
        sqlite3_finalize(st)
        return out.joined(separator: " | ")
    }

    /// The notification's title (for messages, usually the sender), from its stored property list.
    nonisolated private static func title(from statement: OpaquePointer?) -> String {
        guard let bytes = sqlite3_column_blob(statement, 1) else { return "" }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return "" }
        let text = ["titl", "subt", "body"].lazy.compactMap { find($0, in: plist) }.first { !$0.isEmpty }
        if text == nil { log.notice("no title; keys: \(describe(plist), privacy: .public)") }
        return text ?? ""
    }

    /// First string stored under `key`, searching nested dictionaries and arrays.
    nonisolated private static func find(_ key: String, in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            if let s = dict[key] as? String { return s }
            return dict.values.lazy.compactMap { find(key, in: $0) }.first
        }
        if let array = value as? [Any] { return array.lazy.compactMap { find(key, in: $0) }.first }
        return nil
    }

    /// Key names only (no contents), for diagnosing a format change.
    nonisolated private static func describe(_ value: Any) -> String {
        if let dict = value as? [String: Any] {
            return "{" + dict.map { "\($0.key): \(describe($0.value))" }.sorted().joined(separator: ", ") + "}"
        }
        if let array = value as? [Any] { return "[\(array.count)]" }
        return String(describing: type(of: value))
    }

    nonisolated private static func darwinUserDir() -> String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(_CS_DARWIN_USER_DIR, &buffer, buffer.count) > 0 else { return nil }
        return String(cString: buffer)
    }

    static func openFullDiskAccessSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
    }
}

/// Pill for one app's notifications: its icon in greyscale, the newest title, and a count when there
/// are several. Click opens the app; hover shows a close button; right-click to dismiss or hide the app.
struct NotificationPill: View {
    let group: NotificationStore.AppGroup
    let grid: Grid
    let open: () -> Void
    let dismiss: () -> Void
    let hideApp: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        HStack(spacing: 1 * grid.u) {
            Image(nsImage: Self.icon(for: group.bundleID))
                .resizable()
                .frame(width: 2.6 * grid.u, height: 2.6 * grid.u)
                .saturation(0) // monochrome, to match the white-on-glass look
                .opacity(0.9)
            if !group.title.isEmpty {
                Text(group.title).lineLimit(1).frame(maxWidth: 16 * grid.u, alignment: .leading).fixedSize()
            }
            ZStack {
                if group.count > 1 {
                    Text("\(group.count)").monospacedDigit().opacity(hover.on ? 0 : 0.6)
                }
                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill").opacity(0.75)
                }
                .buttonStyle(.plain)
                .opacity(hover.on ? 1 : 0)
                .help("Dismiss")
            }
        }
        .font(.system(size: 1.8 * grid.u, weight: .semibold))
        .padding(.leading, 1.2 * grid.u)
        .padding(.trailing, 1.6 * grid.u)
        .padding(.vertical, 0.9 * grid.u)
        .glass(grid, capsule: true)
        .contentShape(Capsule())
        .onTapGesture(perform: open)
        .onHover { on in withAnimation(.easeOut(duration: 0.2)) { hover.on = on } }
        .contextMenu {
            Button("Dismiss", action: dismiss)
            Button("Never Show \(Self.name(for: group.bundleID))", action: hideApp)
        }
        .transition(Motion.pop)
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return "This App" }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func icon(for bundleID: String) -> NSImage {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return NSImage(systemSymbolName: "app.badge", accessibilityDescription: nil) ?? NSImage()
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    static func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }
}
