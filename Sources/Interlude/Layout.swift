import SwiftUI

/// A card on the standby screen.
enum Widget: String, CaseIterable, Identifiable {
    case battery, calendar, nowPlaying, clock, weather, reminders, worldClock, timer

    var id: Self { self }
    /// Wide cards cover two cells side by side; small ones cover one.
    var wide: Bool { ![.battery, .calendar, .timer].contains(self) }

    var name: String {
        switch self {
        case .battery: "Battery"
        case .calendar: "Calendar"
        case .nowPlaying: "Now Playing"
        case .clock: "Clock"
        case .weather: "Weather"
        case .reminders: "Reminders"
        case .worldClock: "World Clock"
        case .timer: "Focus Timer"
        }
    }

    var symbol: String {
        switch self {
        case .battery: "battery.75percent"
        case .calendar: "calendar"
        case .nowPlaying: "music.note"
        case .clock: "clock"
        case .weather: "cloud.sun"
        case .reminders: "checklist"
        case .worldClock: "globe"
        case .timer: "timer"
        }
    }
}

/// Grid cell: column from the left, row 0–2 from the top.
struct Cell: Hashable {
    var col: Int
    var row: Int
}

/// Where each shown widget sits on the grid that covers the whole screen (3 rows; the column count
/// comes from the screen's shape, see `Grid`). Widgets not in `origins` are on the shelf, not shown.
/// A wide card covers two cells side by side. The pills go in the free space the widgets leave.
/// Stored as text, e.g. "5|battery@3,0;calendar@4,0;nowPlaying@3,1;clock@3,2".
struct WidgetLayout: Equatable, RawRepresentable {
    static let rows = 3

    let columns: Int
    private(set) var origins: [Widget: Cell]

    init(columns: Int, origins: [Widget: Cell]) {
        self.columns = columns
        self.origins = origins
    }

    /// Battery and calendar on top, Now Playing and the clock below, all against the right edge.
    static func standard(columns n: Int) -> WidgetLayout {
        WidgetLayout(columns: n, origins: [
            .battery: Cell(col: n - 2, row: 0), .calendar: Cell(col: n - 1, row: 0),
            .nowPlaying: Cell(col: n - 2, row: 1), .clock: Cell(col: n - 2, row: 2),
        ])
    }

    /// This layout if it was made for a screen with this many columns, otherwise the default.
    func fitted(to columns: Int) -> WidgetLayout { self.columns == columns ? self : .standard(columns: columns) }

    var allCells: [Cell] { (0..<Self.rows).flatMap { r in (0..<columns).map { Cell(col: $0, row: r) } } }

    /// Shown widgets, in a fixed order.
    var placed: [Widget] { Widget.allCases.filter { origins[$0] != nil } }
    /// Widgets on the shelf.
    var shelf: [Widget] { Widget.allCases.filter { origins[$0] == nil } }

    /// Rejects anything off the grid or overlapping, so a bad or old saved value falls back to the default.
    init?(rawValue: String) {
        let halves = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        guard halves.count == 2, let columns = Int(halves[0]), (3...10).contains(columns) else { return nil }
        var origins: [Widget: Cell] = [:]
        for part in halves[1].split(separator: ";") {
            let bits = part.split(separator: "@")
            guard bits.count == 2, let w = Widget(rawValue: String(bits[0])) else { return nil }
            let xy = bits[1].split(separator: ",").compactMap { Int($0) }
            guard xy.count == 2 else { return nil }
            origins[w] = Cell(col: xy[0], row: xy[1])
        }
        let layout = WidgetLayout(columns: columns, origins: origins)
        guard origins.allSatisfy({ layout.fits($0.key, at: $0.value) }) else { return nil }
        self = layout
    }

    var rawValue: String {
        "\(columns)|" + placed.map { w in "\(w.rawValue)@\(origins[w]!.col),\(origins[w]!.row)" }.joined(separator: ";")
    }

    func origin(of widget: Widget) -> Cell? { origins[widget] }

    static func cells(_ widget: Widget, at origin: Cell) -> [Cell] {
        widget.wide ? [origin, Cell(col: origin.col + 1, row: origin.row)] : [origin]
    }

    /// The widget covering a cell, if any.
    func occupant(of cell: Cell) -> Widget? {
        origins.first { Self.cells($0.key, at: $0.value).contains(cell) }?.key
    }

    /// Wholly on the grid and not overlapping any other widget.
    private func fits(_ widget: Widget, at origin: Cell) -> Bool {
        let mine = Self.cells(widget, at: origin)
        guard mine.allSatisfy({ (0..<Self.rows).contains($0.row) && (0..<columns).contains($0.col) }) else { return false }
        return origins.allSatisfy { other, o in other == widget || Set(mine).isDisjoint(with: Self.cells(other, at: o)) }
    }

    /// Where a widget dropped on `cell` lands: a wide card dropped on the last column shifts left one.
    func landing(_ widget: Widget, on cell: Cell) -> Cell {
        widget.wide ? Cell(col: min(cell.col, columns - 2), row: cell.row) : cell
    }

    /// Nearest free spot for a widget, or nil if it fits nowhere.
    private func nearestSpot(for widget: Widget, to cell: Cell) -> Cell? {
        allCells.sorted { abs($0.col - cell.col) + abs($0.row - cell.row) < abs($1.col - cell.col) + abs($1.row - cell.row) }
            .first { fits(widget, at: $0) }
    }

    /// Moves a widget (from the grid or the shelf) to a cell. Widgets in the way move into the space it
    /// left (keeping their offset, so two widgets trade places), else to the nearest free spot, else to
    /// the shelf. Returns false if nothing changed.
    @discardableResult
    mutating func move(_ widget: Widget, to cell: Cell) -> Bool {
        let target = landing(widget, on: cell)
        let old = origins[widget]
        let covered = Set(Self.cells(widget, at: target))
        guard target != old, covered.allSatisfy({ (0..<Self.rows).contains($0.row) && (0..<columns).contains($0.col) })
        else { return false }
        let displaced = placed.filter { $0 != widget && !covered.isDisjoint(with: Self.cells($0, at: origins[$0]!)) }
        var next = WidgetLayout(columns: columns, origins: origins.filter { !displaced.contains($0.key) })
        next.origins[widget] = target
        for d in displaced {
            let o = origins[d]!
            let shifted = old.map { Cell(col: o.col + $0.col - target.col, row: o.row + $0.row - target.row) } ?? o
            next.origins[d] = next.nearestSpot(for: d, to: shifted)
        }
        self = next
        return true
    }

    /// Puts a shelf widget on the grid at the free spot nearest the top-left. False if there's no room.
    @discardableResult
    mutating func add(_ widget: Widget) -> Bool {
        guard origins[widget] == nil, let spot = nearestSpot(for: widget, to: Cell(col: 0, row: 0)) else { return false }
        origins[widget] = spot
        return true
    }

    /// Takes a widget off the screen, onto the shelf.
    mutating func remove(_ widget: Widget) { origins[widget] = nil }

    /// Moves a widget one cell in a direction.
    @discardableResult
    mutating func nudge(_ widget: Widget, dx: Int, dy: Int) -> Bool {
        guard let o = origins[widget] else { return false }
        return move(widget, to: Cell(col: o.col + dx, row: o.row + dy))
    }

    /// Where the pills go: the longest run of free cells in the top row, else the bottom row,
    /// else the middle one. Nil only if every cell is taken.
    var pillsRun: (row: Int, cols: ClosedRange<Int>)? {
        for row in [0, Self.rows - 1, 1] {
            var best: ClosedRange<Int>?
            var start: Int?
            for col in 0...columns {
                let free = col < columns && occupant(of: Cell(col: col, row: row)) == nil
                if free, start == nil { start = col }
                if !free, let s = start {
                    if (col - 1) - s > (best.map { $0.upperBound - $0.lowerBound } ?? -1) { best = s...(col - 1) }
                    start = nil
                }
            }
            if let best { return (row, best) }
        }
        return nil
    }
}

/// A saved layout for one situation. Music and Night are used only when switched on in Settings.
enum LayoutProfile: String, CaseIterable, Identifiable {
    case standard, music, night

    var id: Self { self }
    var key: String { self == .standard ? "widgetLayout" : "widgetLayout.\(rawValue)" }
    var enabledKey: String { "widgetLayout.\(rawValue).on" }

    var name: String {
        switch self {
        case .standard: "Standard"
        case .music: "Music"
        case .night: "Night"
        }
    }

    /// The layout to show right now: Night beats Music, and either only when switched on.
    static func active(music: Bool, night: Bool) -> LayoutProfile {
        let d = UserDefaults.standard
        if night, d.bool(forKey: LayoutProfile.night.enabledKey) { return .night }
        if music, d.bool(forKey: LayoutProfile.music.enabledKey) { return .music }
        return .standard
    }
}

extension Grid {
    /// The pills' area and how they line up in it: at the top of a top or middle row, at the bottom of
    /// the bottom row; against the right edge when the free space touches it and not the left one.
    func pillsArea(_ layout: WidgetLayout) -> (x: CGFloat, width: CGFloat, y: CGFloat, alignment: Alignment) {
        guard let run = layout.pillsRun else { return (margin, 0, margin, .topLeading) }
        let left = x(run.cols.lowerBound)
        let width = x(run.cols.upperBound) + cw - left
        let trailing = run.cols.upperBound == layout.columns - 1 && run.cols.lowerBound > 0
        let bottom = run.row == WidgetLayout.rows - 1
        let alignment: Alignment = switch (bottom, trailing) {
        case (false, false): .topLeading
        case (false, true): .topTrailing
        case (true, false): .bottomLeading
        case (true, true): .bottomTrailing
        }
        return (left, width, y(run.row), alignment)
    }
}

// MARK: - Settings pane

/// The whole screen in miniature: drag widgets between the grid and the shelf below it.
/// One layout per situation (Standard, Music, Night).
struct LayoutSettings: View {
    @AppStorage("settingsLayoutProfile") private var profile = LayoutProfile.standard

    var body: some View {
        Form {
            Section {
                Picker("Layout", selection: $profile) {
                    ForEach(LayoutProfile.allCases) { Text($0.name).tag($0) }
                }
                .pickerStyle(.segmented)
                ProfileToggle(profile: profile)
            } footer: {
                Text(profile == .standard
                     ? "Shown unless a Music or Night layout applies."
                     : profile == .music ? "Shown while music plays." : "Shown while night mode is on.")
                    .foregroundStyle(.secondary)
            }
            ProfileEditor(profile: profile).id(profile)
        }
        .formStyle(.grouped)
    }
}

private struct ProfileToggle: View {
    let profile: LayoutProfile
    @AppStorage private var on: Bool

    init(profile: LayoutProfile) {
        self.profile = profile
        _on = AppStorage(wrappedValue: false, profile.enabledKey)
    }

    var body: some View {
        if profile != .standard {
            Toggle(profile == .music ? "Use a different layout while music plays" : "Use a different layout at night", isOn: $on)
        }
    }
}

private struct ProfileEditor: View {
    let profile: LayoutProfile
    @AppStorage private var stored: WidgetLayout

    init(profile: LayoutProfile) {
        self.profile = profile
        _stored = AppStorage(wrappedValue: WidgetLayout.standard(columns: 5), profile.key)
    }

    var body: some View {
        // Same shape as the screen standby runs on, so the grid has the same columns. The picture
        // grows with the window.
        let screen = NSScreen.main?.frame.size ?? CGSize(width: 1512, height: 982)
        let columns = Grid(size: screen).columns
        let layout = Binding { stored.fitted(to: columns) } set: { stored = $0 }
        let standard = WidgetLayout.standard(columns: columns)
        Section {
            GeometryReader { geo in
                ScreenPreview(layout: layout, grid: Grid(size: CGSize(width: geo.size.width, height: geo.size.width * screen.height / screen.width)))
            }
            .aspectRatio(screen.width / screen.height, contentMode: .fit)
            .listRowInsets(EdgeInsets())
        } footer: {
            Text("Drag a widget anywhere on the screen; widgets in the way swap places with it. Click − to remove a widget. Notification and calendar pills fill the space the widgets leave free.")
                .foregroundStyle(.secondary)
        }
        Section {
            Gallery(layout: layout)
        } header: {
            Text("Add Widgets")
        } footer: {
            Text("Click + to add a widget, or drag it onto the screen above.")
                .foregroundStyle(.secondary)
        }
        Section {
            Button("Reset to Default") { withAnimation(Motion.layout) { stored = standard } }
                .disabled(layout.wrappedValue == standard)
        }
    }
}

/// The widget being dragged and the cell under the pointer. (A model object: no SwiftUI macros here.)
final class DragState: ObservableObject {
    @Published var widget: Widget?
    @Published var cell: Cell?
    @Published var overShelf = false
}

/// One drag state shared by the grid and the shelf.
@MainActor private let sharedDrag = DragState()

private struct ScreenPreview: View {
    @Binding var layout: WidgetLayout
    let grid: Grid
    @ObservedObject private var drag = sharedDrag

    var body: some View {
        let pills = grid.pillsArea(layout)
        ZStack(alignment: .topLeading) {
            // A neutral screen: the editor shows placement, not colour.
            LinearGradient(colors: [Color(white: 0.32), Color(white: 0.14)], startPoint: .top, endPoint: .bottom)

            ForEach(layout.allCells, id: \.self) { cell in
                RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .frame(width: grid.cw, height: grid.s)
                    .offset(x: grid.x(cell.col), y: grid.y(cell.row))
            }

            HStack(spacing: grid.u) {
                ForEach(0..<2, id: \.self) { _ in
                    Capsule().fill(.white.opacity(0.3)).frame(width: 9 * grid.u, height: 3.2 * grid.u)
                }
            }
            .frame(width: max(pills.width, 1), height: grid.s, alignment: pills.alignment)
            .clipped()
            .offset(x: pills.x, y: pills.y)
            .accessibilityHidden(true)

            if let w = drag.widget, let c = drag.cell {
                let o = layout.landing(w, on: c)
                RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
                    .fill(.white.opacity(0.25))
                    .frame(width: w.wide ? grid.wide : grid.cw, height: grid.s)
                    .offset(x: grid.x(o.col), y: grid.y(o.row))
                    .allowsHitTesting(false)
            }

            ForEach(layout.placed) { tile($0, at: layout.origin(of: $0)!) }
        }
        .frame(width: grid.width, height: grid.column + 2 * grid.margin, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .onDrop(of: [.text], delegate: GridDrop(layout: $layout, drag: drag, grid: grid))
        .animation(Motion.layout, value: layout)
    }

    private func tile(_ widget: Widget, at o: Cell) -> some View {
        let shape = RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
        return VStack(spacing: 4) {
            Image(systemName: widget.symbol).font(.title2)
            Text(widget.name).font(.callout).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(.white)
        .frame(width: widget.wide ? grid.wide : grid.cw, height: grid.s)
        .background(shape.fill(.white.opacity(0.16)))
        .overlay(shape.strokeBorder(.white.opacity(0.3), lineWidth: 1))
        .contentShape(shape)
        .onDrag {
            drag.widget = widget
            return NSItemProvider(object: widget.rawValue as NSString)
        }
        .overlay(alignment: .topLeading) {
            Badge(symbol: "minus", label: "Remove \(widget.name)") { change { $0.remove(widget) } }
                .offset(x: -7, y: -7)
        }
        .offset(x: grid.x(o.col), y: grid.y(o.row))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(widget.name), column \(o.col + 1), row \(o.row + 1)")
        .accessibilityAction(named: "Move Up") { change { $0.nudge(widget, dx: 0, dy: -1) } }
        .accessibilityAction(named: "Move Down") { change { $0.nudge(widget, dx: 0, dy: 1) } }
        .accessibilityAction(named: "Move Left") { change { $0.nudge(widget, dx: -1, dy: 0) } }
        .accessibilityAction(named: "Move Right") { change { $0.nudge(widget, dx: 1, dy: 0) } }
        .accessibilityAction(named: "Remove from Screen") { change { $0.remove(widget) } }
    }

    private func change(_ edit: (inout WidgetLayout) -> Void) {
        withAnimation(Motion.layout) { edit(&layout) }
    }
}

/// The round − / + button in a widget's corner, as when editing widgets on the Mac desktop.
private struct Badge: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.black)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.white).shadow(color: .black.opacity(0.3), radius: 2, y: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Widgets not on the screen, as small tiles with a + in the corner. Dropping a widget here removes it.
private struct Gallery: View {
    @Binding var layout: WidgetLayout
    @ObservedObject private var drag = sharedDrag

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 14) {
            ForEach(layout.shelf) { widget in
                VStack(spacing: 6) {
                    Image(systemName: widget.symbol).font(.title2)
                    Text(widget.name).font(.callout)
                    Text(widget.wide ? "Medium" : "Small").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 92)
                .background(shape.fill(.quaternary))
                .contentShape(shape)
                .overlay(alignment: .topLeading) {
                    Badge(symbol: "plus", label: "Add \(widget.name)") {
                        withAnimation(Motion.layout) { _ = layout.add(widget) }
                    }
                    .offset(x: -6, y: -6)
                }
                .onDrag {
                    drag.widget = widget
                    return NSItemProvider(object: widget.rawValue as NSString)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, minHeight: 60)
        .overlay {
            if layout.shelf.isEmpty {
                Text("Every widget is on the screen. Drag one here to remove it.").foregroundStyle(.secondary)
            }
        }
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(drag.overShelf ? Color.accentColor : .clear, lineWidth: 2))
        .onDrop(of: [.text], delegate: ShelfDrop(layout: $layout, drag: drag))
        .animation(Motion.layout, value: layout)
    }
}

/// Turns the pointer position into a cell and moves the dragged widget there on drop.
private struct GridDrop: DropDelegate {
    @Binding var layout: WidgetLayout
    let drag: DragState
    let grid: Grid

    private func cell(at p: CGPoint) -> Cell? {
        let pitch = grid.s + grid.g
        let row = Int((p.y - grid.margin) / pitch)
        guard p.y >= grid.margin, row < WidgetLayout.rows else { return nil }
        // Nearest column by centre, so gaps and margins snap to a cell.
        let col = (0..<grid.columns).min { abs(grid.x($0) + grid.cw / 2 - p.x) < abs(grid.x($1) + grid.cw / 2 - p.x) }!
        return Cell(col: col, row: row)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let c = cell(at: info.location)
        if c != drag.cell { drag.cell = c }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) { drag.cell = nil }

    func performDrop(info: DropInfo) -> Bool {
        defer { drag.widget = nil; drag.cell = nil }
        guard let w = drag.widget, let c = cell(at: info.location) else { return false }
        withAnimation(Motion.layout) { _ = layout.move(w, to: c) }
        return true
    }
}

/// Dropping a widget on the shelf hides it.
private struct ShelfDrop: DropDelegate {
    @Binding var layout: WidgetLayout
    let drag: DragState

    func dropEntered(info: DropInfo) { drag.overShelf = true }
    func dropExited(info: DropInfo) { drag.overShelf = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { drag.widget = nil; drag.overShelf = false }
        guard let w = drag.widget else { return false }
        withAnimation(Motion.layout) { layout.remove(w) }
        return true
    }
}
