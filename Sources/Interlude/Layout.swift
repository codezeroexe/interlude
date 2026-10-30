import CoreImage
import SwiftUI

/// A card on the standby screen.
enum Widget: String, CaseIterable, Identifiable {
    case battery, calendar, nowPlaying, clock, weather, reminders, worldClock, timer

    var id: Self { self }

    /// The sizes this widget comes in. No widget is tall and narrow (1×2).
    var sizes: [WidgetSize] {
        switch self {
        case .clock: [.small, .medium, .large, .extraLarge]
        case .battery, .timer: [.small, .medium]
        default: [.small, .medium, .large]
        }
    }

    /// The size a widget gets when added, and for layouts saved before widgets had sizes.
    var defaultSize: WidgetSize { [.battery, .calendar, .timer].contains(self) ? .small : .medium }

    /// Names of the styles this widget has at a size. Style 0 is the first.
    func styles(_ size: WidgetSize) -> [String] {
        switch (self, size) {
        case (.clock, .small): ["Stacked", "Analog"]
        case (.clock, .medium): ["Classic", "Centred"]
        case (.clock, .large): ["Stacked", "Analog"]
        case (.clock, .extraLarge): ["Big", "With Info"]
        case (.weather, .small): ["Now", "Symbol"]
        case (.weather, .medium): ["Hours", "Days"]
        case (.weather, .large): ["Forecast", "Details"]
        case (.calendar, .small): ["Month", "Next Event"]
        case (.calendar, .medium): ["Today", "Month"]
        case (.calendar, .large): ["Month", "Agenda"]
        case (.nowPlaying, .small): ["Fade", "Pill", "Thumbnail"]
        case (.nowPlaying, .medium): ["Classic", "Fade", "Pill"]
        case (.nowPlaying, .large): ["Fade", "Panel"]
        case (.battery, .small): ["This Mac", "Devices"]
        case (.battery, .medium): ["Rings", "List"]
        case (.reminders, .small): ["List", "Count"]
        case (.reminders, .medium): ["Classic", "Columns"]
        case (.reminders, .large): ["List", "By Day"]
        case (.worldClock, .small): ["Analog", "Digital"]
        case (.worldClock, .medium): ["Analog", "Digital"]
        case (.worldClock, .large): ["Analog", "Digital"]
        case (.timer, .small): ["Ring", "Digits"]
        case (.timer, .medium): ["Ring", "Digits"]
        default: ["Default"]
        }
    }

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

/// How many cells a widget covers: columns × rows.
enum WidgetSize: String, CaseIterable, Identifiable {
    case small = "S", medium = "M", large = "L", extraLarge = "XL"

    var id: Self { self }
    var cols: Int { switch self { case .small: 1; case .medium, .large: 2; case .extraLarge: 4 } }
    var rows: Int { self == .small || self == .medium ? 1 : 2 }

    var name: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .extraLarge: "Extra Large"
        }
    }
}

/// Grid cell: column from the left, row 0–2 from the top.
struct Cell: Hashable {
    var col: Int
    var row: Int
}

/// Where each shown widget sits on the grid that covers the whole screen (3 rows; the column count
/// comes from the screen's shape, see `Grid`), and its size and style. Widgets not in `origins` are on
/// the shelf, not shown.
/// Stored as text, e.g. "5|battery@3,0;clock@3,1,L,1" (column, row, size, style). Size and style are
/// optional, so layouts saved before widgets had sizes still load.
struct WidgetLayout: Equatable, RawRepresentable {
    let columns: Int
    let rows: Int
    private(set) var origins: [Widget: Cell]
    private(set) var sizes: [Widget: WidgetSize] = [:]
    private(set) var styles: [Widget: Int] = [:]

    init(columns: Int, rows: Int = 3, origins: [Widget: Cell]) {
        self.columns = columns
        self.rows = rows
        self.origins = origins
    }

    /// Battery and calendar on top, Now Playing and the clock below, all against the right edge.
    /// On other grid sizes: the same four, each at the free spot nearest the top-right.
    static func standard(columns n: Int, rows: Int = 3) -> WidgetLayout {
        if rows == 3, n >= 2 {
            return WidgetLayout(columns: n, origins: [
                .battery: Cell(col: n - 2, row: 0), .calendar: Cell(col: n - 1, row: 0),
                .nowPlaying: Cell(col: n - 2, row: 1), .clock: Cell(col: n - 2, row: 2),
            ])
        }
        var layout = WidgetLayout(columns: n, rows: rows, origins: [:])
        for w in [Widget.clock, .nowPlaying, .battery, .calendar] {
            if let spot = layout.nearestSpot(for: w, to: Cell(col: n - 1, row: 0)) { layout.origins[w] = spot }
        }
        return layout
    }

    /// This layout if it was made for a grid of this shape, otherwise the default.
    func fitted(to columns: Int, rows: Int = 3) -> WidgetLayout {
        self.columns == columns && self.rows == rows ? self : .standard(columns: columns, rows: rows)
    }

    /// Whether a size fits on this grid at all.
    func allows(_ size: WidgetSize) -> Bool { size.cols <= columns && size.rows <= rows }

    var allCells: [Cell] { (0..<rows).flatMap { r in (0..<columns).map { Cell(col: $0, row: r) } } }

    /// Shown widgets, in a fixed order.
    var placed: [Widget] { Widget.allCases.filter { origins[$0] != nil } }
    /// Widgets on the shelf.
    var shelf: [Widget] { Widget.allCases.filter { origins[$0] == nil } }

    /// Rejects anything off the grid or overlapping, so a bad or old saved value falls back to the default.
    init?(rawValue: String) {
        let halves = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        guard halves.count == 2 else { return nil }
        // "5|…" (3 rows, from before the grid size setting) or "5x4|…".
        let shape = halves[0].split(separator: "x").compactMap { Int($0) }
        guard let columns = shape.first, (2...10).contains(columns) else { return nil }
        let rows = shape.count > 1 ? shape[1] : 3
        guard (2...4).contains(rows) else { return nil }
        var layout = WidgetLayout(columns: columns, rows: rows, origins: [:])
        for part in halves[1].split(separator: ";") {
            let bits = part.split(separator: "@")
            guard bits.count == 2, let w = Widget(rawValue: String(bits[0])) else { return nil }
            let fields = bits[1].split(separator: ",").map(String.init)
            guard fields.count >= 2, let col = Int(fields[0]), let row = Int(fields[1]) else { return nil }
            layout.origins[w] = Cell(col: col, row: row)
            if fields.count >= 3 {
                guard let size = WidgetSize(rawValue: fields[2]), w.sizes.contains(size) else { return nil }
                layout.sizes[w] = size
            }
            if fields.count >= 4, let style = Int(fields[3]) { layout.styles[w] = style }
        }
        guard layout.origins.allSatisfy({ layout.fits($0.key, at: $0.value, size: layout.size(of: $0.key)) }) else { return nil }
        self = layout
    }

    var rawValue: String {
        (rows == 3 ? "\(columns)|" : "\(columns)x\(rows)|") + placed.map { w in
            let o = origins[w]!
            return "\(w.rawValue)@\(o.col),\(o.row),\(size(of: w).rawValue),\(style(of: w))"
        }.joined(separator: ";")
    }

    func origin(of widget: Widget) -> Cell? { origins[widget] }
    func size(of widget: Widget) -> WidgetSize { sizes[widget] ?? widget.defaultSize }
    /// The chosen style, kept in range for the widget's current size.
    func style(of widget: Widget) -> Int { min(styles[widget] ?? 0, widget.styles(size(of: widget)).count - 1) }

    static func cells(at origin: Cell, size: WidgetSize) -> [Cell] {
        (0..<size.rows).flatMap { r in (0..<size.cols).map { Cell(col: origin.col + $0, row: origin.row + r) } }
    }

    func cells(_ widget: Widget) -> [Cell] {
        origins[widget].map { Self.cells(at: $0, size: size(of: widget)) } ?? []
    }

    /// The widget covering a cell, if any.
    func occupant(of cell: Cell) -> Widget? {
        placed.first { cells($0).contains(cell) }
    }

    private func onGrid(_ cells: [Cell]) -> Bool {
        cells.allSatisfy { (0..<rows).contains($0.row) && (0..<columns).contains($0.col) }
    }

    /// Wholly on the grid and not overlapping any other widget.
    private func fits(_ widget: Widget, at origin: Cell, size: WidgetSize) -> Bool {
        let mine = Self.cells(at: origin, size: size)
        guard onGrid(mine) else { return false }
        return placed.allSatisfy { $0 == widget || Set(mine).isDisjoint(with: cells($0)) }
    }

    /// Where a widget dropped on `cell` lands: shifted left and up as needed to stay on the grid.
    func landing(_ widget: Widget, on cell: Cell) -> Cell { clamp(cell, size(of: widget)) }

    private func clamp(_ cell: Cell, _ size: WidgetSize) -> Cell {
        Cell(col: max(0, min(cell.col, columns - size.cols)), row: max(0, min(cell.row, rows - size.rows)))
    }

    /// Nearest free spot for a widget, or nil if it fits nowhere.
    private func nearestSpot(for widget: Widget, to cell: Cell) -> Cell? {
        let size = size(of: widget)
        return allCells.sorted { abs($0.col - cell.col) + abs($0.row - cell.row) < abs($1.col - cell.col) + abs($1.row - cell.row) }
            .first { fits(widget, at: $0, size: size) }
    }

    /// Puts a widget at a spot with a size. Widgets in the way move into the space it left (keeping
    /// their offset, so two widgets trade places), else to the nearest free spot, else to the shelf.
    private mutating func place(_ widget: Widget, at target: Cell, size: WidgetSize) {
        let old = origins[widget]
        let covered = Set(Self.cells(at: target, size: size))
        let displaced = placed.filter { $0 != widget && !covered.isDisjoint(with: cells($0)) }
        var next = self
        for d in displaced { next.origins[d] = nil }
        next.origins[widget] = target
        next.sizes[widget] = size
        for d in displaced {
            let o = origins[d]!
            let shifted = old.map { Cell(col: o.col + $0.col - target.col, row: o.row + $0.row - target.row) } ?? o
            next.origins[d] = next.nearestSpot(for: d, to: shifted)
        }
        self = next
    }

    /// Moves a widget (from the grid or the shelf) to a cell. Returns false if nothing changed.
    @discardableResult
    mutating func move(_ widget: Widget, to cell: Cell) -> Bool {
        let target = landing(widget, on: cell)
        guard target != origins[widget] else { return false }
        place(widget, at: target, size: size(of: widget))
        return true
    }

    /// Changes a widget's size, keeping its top-left corner where it can. Widgets in the way move aside.
    @discardableResult
    mutating func resize(_ widget: Widget, to size: WidgetSize) -> Bool {
        guard widget.sizes.contains(size), allows(size), size != self.size(of: widget) else { return false }
        guard let o = origins[widget] else { sizes[widget] = size; return true }
        place(widget, at: clamp(o, size), size: size)
        return true
    }

    mutating func setStyle(_ widget: Widget, _ style: Int) { styles[widget] = style }

    /// Puts a shelf widget on the grid at the free spot nearest the top-left, trying smaller sizes if
    /// its own doesn't fit. False if there's no room.
    @discardableResult
    mutating func add(_ widget: Widget) -> Bool {
        guard origins[widget] == nil else { return false }
        let tries = [size(of: widget)] + widget.sizes.filter { $0.cols * $0.rows < size(of: widget).cols * size(of: widget).rows }.reversed()
        for size in tries where allows(size) {
            sizes[widget] = size
            if let spot = nearestSpot(for: widget, to: Cell(col: 0, row: 0)) {
                origins[widget] = spot
                return true
            }
        }
        sizes[widget] = tries.first
        return false
    }

    /// Takes a widget off the screen, onto the shelf.
    mutating func remove(_ widget: Widget) { origins[widget] = nil }

    /// Moves a widget one cell in a direction.
    @discardableResult
    mutating func nudge(_ widget: Widget, dx: Int, dy: Int) -> Bool {
        guard let o = origins[widget] else { return false }
        return move(widget, to: Cell(col: o.col + dx, row: o.row + dy))
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
        case .standard: "Everyday"
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

// MARK: - Settings pane

/// The whole screen in miniature: drag widgets between the grid and the shelf below it.
/// One layout per situation (Everyday, Music, Night).
struct LayoutSettings: View {
    let model: OverlayModel
    @AppStorage("settingsLayoutProfile") private var profile = LayoutProfile.standard
    @AppStorage(GridSize.key) private var gridRows = 3

    var body: some View {
        SettingsPage {
            SettingsGroup(footer: "Changing the grid size starts each layout again from the default.") {
                SettingsRow(title: "Grid size", subtitle: "Fewer rows make every card bigger") {
                    Segmented(selection: $gridRows, choices: GridSize.choices.map { Choice(GridSize.name($0), $0) })
                }
            }
            .padding(.top, 6)
            SettingsGroup(footer: profile == .standard
                          ? "Everyday shows unless a Music or Night layout applies."
                          : profile == .music ? "Shown while music plays." : "Shown while night mode is on.") {
                SettingsRow(title: "Layout") {
                    Segmented(selection: $profile, choices: LayoutProfile.allCases.map { Choice($0.name, $0) })
                }
                ProfileToggle(profile: profile)
            }
            ProfileEditor(model: model, profile: profile).id(profile)
        }
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
            let title = profile == .music ? "Use a different layout while music plays" : "Use a different layout at night"
            SettingsRow(title: title) { Toggle(title, isOn: $on).labelsHidden() }
        }
    }
}

private struct ProfileEditor: View {
    let model: OverlayModel
    let profile: LayoutProfile
    @AppStorage private var stored: WidgetLayout
    @AppStorage(GridSize.key) private var gridRows = 3

    init(model: OverlayModel, profile: LayoutProfile) {
        self.model = model
        self.profile = profile
        _stored = AppStorage(wrappedValue: WidgetLayout.standard(columns: 5), profile.key)
    }

    var body: some View {
        // Same shape as the screen standby runs on, so the grid has the same columns. The picture
        // grows with the window.
        let screen = StartConditions.screen?.frame.size ?? CGSize(width: 1512, height: 982)
        let columns = Grid(size: screen, rows: gridRows).columns
        let layout = Binding { stored.fitted(to: columns, rows: gridRows) } set: { stored = $0 }
        let standard = WidgetLayout.standard(columns: columns, rows: gridRows)
        VStack(alignment: .leading, spacing: 6) {
            Text("Screen")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
            GeometryReader { geo in
                ScreenPreview(model: model, layout: layout,
                              grid: Grid(size: CGSize(width: geo.size.width, height: geo.size.width * screen.height / screen.width), rows: gridRows))
            }
            .aspectRatio(screen.width / screen.height, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text("Drag a card to move it; cards in the way swap places. Click a card to change its size and style, or − to remove it.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
        }
        WidgetOptions(model: model, layout: layout)
        SettingsGroup(title: "Add Widgets", footer: "Click + to add a widget, or drag it onto the screen above.") {
            Gallery(model: model, layout: layout)
        }
        HStack {
            Spacer()
            Button("Reset to Default") { withAnimation(Motion.layout) { stored = standard } }
                .buttonStyle(.capsule)
                .disabled(layout.wrappedValue == standard)
        }
    }
}

/// The widget being dragged and the cell under the pointer. (A model object: no SwiftUI macros here.)
final class DragState: ObservableObject {
    @Published var widget: Widget?
    @Published var cell: Cell?
    @Published var overShelf = false
    /// The widget picked on the screen preview, whose size and style the bar below it changes.
    @Published var selected: Widget?
}

/// One drag state shared by the grid and the shelf.
@MainActor private let sharedDrag = DragState()

/// The wallpaper still behind card previews in Settings; a dusk gradient if it's missing.
struct PreviewBackdrop: View {
    /// The renderer swaps this for other wallpapers.
    static var image = Bundle.main.url(forResource: "backdrop", withExtension: "jpg").flatMap(NSImage.init(contentsOf:)) {
        didSet { blurs = [:] }
    }
    private static var blurs: [Int: NSImage] = [:]

    /// The still, blurred by `radius` of its own pixels. For hand-drawn glass in off-screen renders.
    static func blurred(_ radius: CGFloat) -> NSImage {
        guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return NSImage() }
        let key = Int(radius.rounded())
        if let done = blurs[key] { return done }
        let input = CIImage(cgImage: cg)
        let output = input.clampedToExtent().applyingGaussianBlur(sigma: Double(key) / 2).cropped(to: input.extent)
        guard let out = CIContext().createCGImage(output, from: input.extent) else { return image }
        let result = NSImage(cgImage: out, size: image.size)
        blurs[key] = result
        return result
    }

    var body: some View {
        if let image = Self.image {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            LinearGradient(colors: [Color(red: 0.04, green: 0.08, blue: 0.19), Color(red: 0.18, green: 0.16, blue: 0.39),
                                    Color(red: 0.54, green: 0.31, blue: 0.48), Color(red: 0.94, green: 0.63, blue: 0.44)],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// A card as it looks on the standby screen, for previews in Settings: not clickable, and a placeholder
/// track for Now Playing when no player has a song loaded.
struct CardPreview: View {
    let model: OverlayModel
    let widget: Widget
    let size: WidgetSize
    let style: Int
    let grid: Grid
    @ObservedObject private var nowPlaying: NowPlaying

    init(model: OverlayModel, widget: Widget, size: WidgetSize, style: Int, grid: Grid) {
        self.model = model
        self.widget = widget
        self.size = size
        self.style = style
        self.grid = grid
        nowPlaying = model.nowPlaying
    }

    var body: some View {
        Group {
            if widget == .nowPlaying && nowPlaying.track == nil {
                NowPlayingCard(nowPlaying: .sample, grid: grid, size: size, style: style)
            } else {
                WidgetCardView(model: model, widget: widget, size: size, style: style, grid: grid)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }
}

private struct ScreenPreview: View {
    let model: OverlayModel
    @Binding var layout: WidgetLayout
    let grid: Grid
    @ObservedObject private var drag = sharedDrag

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The real cards on a wallpaper still, as standby will look.
            PreviewBackdrop()
                .frame(width: grid.width, height: grid.column + 2 * grid.margin)
                .clipped()
                .overlay(Color.black.opacity(0.15))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.smooth(duration: 0.2)) { drag.selected = nil } }

            ForEach(layout.allCells, id: \.self) { cell in
                RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .allowsHitTesting(false)
                    .frame(width: grid.cw, height: grid.s)
                    .offset(x: grid.x(cell.col), y: grid.y(cell.row))
            }

            if let w = drag.widget, let c = drag.cell {
                let o = layout.landing(w, on: c)
                RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
                    .fill(.white.opacity(0.25))
                    .frame(width: grid.w(layout.size(of: w)), height: grid.h(layout.size(of: w)))
                    .offset(x: grid.x(o.col), y: grid.y(o.row))
                    .allowsHitTesting(false)
            }

            ForEach(layout.placed) { tile($0, at: layout.origin(of: $0)!) }
        }
        .frame(width: grid.width, height: grid.column + 2 * grid.margin, alignment: .topLeading)
        .frostBackdrop(CGSize(width: grid.width, height: grid.column + 2 * grid.margin))
        .frame(maxWidth: .infinity)
        .onDrop(of: [.text], delegate: GridDrop(layout: $layout, drag: drag, grid: grid))
        .animation(Motion.layout, value: layout)
    }

    private func tile(_ widget: Widget, at o: Cell) -> some View {
        let shape = RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
        let size = layout.size(of: widget)
        let selected = drag.selected == widget
        return CardPreview(model: model, widget: widget, size: size, style: layout.style(of: widget), grid: grid)
        .overlay(shape.strokeBorder(.white, lineWidth: 2).opacity(selected ? 1 : 0))
        .shadow(color: .white.opacity(selected ? 0.35 : 0), radius: 6)
        .contentShape(shape)
        .onTapGesture { withAnimation(.smooth(duration: 0.2)) { drag.selected = selected ? nil : widget } }
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
        .accessibilityLabel("\(widget.name), \(size.name), column \(o.col + 1), row \(o.row + 1)")
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
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

/// Size and style for the widget picked on the screen preview: a size picker, then a preview of
/// each style to click.
private struct WidgetOptions: View {
    let model: OverlayModel
    @Binding var layout: WidgetLayout
    @ObservedObject private var drag = sharedDrag

    var body: some View {
        if let widget = drag.selected, layout.origin(of: widget) != nil {
            let size = layout.size(of: widget)
            let styles = widget.styles(size)
            SettingsGroup(title: "Selected: \(widget.name)", footer: "A bigger size moves cards in the way, or off the screen if there's no room.") {
                SettingsRow(title: "Size") {
                    HStack(spacing: 10) {
                        Segmented(selection: Binding { size } set: { new in
                            withAnimation(Motion.layout) { _ = layout.resize(widget, to: new) }
                        }, choices: widget.sizes.filter(layout.allows).map { Choice($0.name, $0) })
                        Button("Done") { withAnimation(.smooth(duration: 0.2)) { drag.selected = nil } }
                            .buttonStyle(.capsule)
                    }
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(styles.indices, id: \.self) { i in
                            StyleThumb(model: model, widget: widget, size: size, style: i, name: styles[i],
                                       selected: layout.style(of: widget) == i) {
                                withAnimation(Motion.layout) { layout.setStyle(widget, i) }
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

/// One style of a widget, drawn small on the wallpaper, with its name. Click to use it.
private struct StyleThumb: View {
    let model: OverlayModel
    let widget: Widget
    let size: WidgetSize
    let style: Int
    let name: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        let grid = Grid.preview(u: size == .extraLarge ? 2.4 : 3.2)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                CardPreview(model: model, widget: widget, size: size, style: style, grid: grid)
                    .padding(10)
                    .background(PreviewBackdrop().allowsHitTesting(false))
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(Color.graphite, lineWidth: 2.5).opacity(selected ? 1 : 0))
                Text(name)
                    .font(.callout)
                    .fontWeight(selected ? .semibold : .regular)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name) style")
        .accessibilityAddTraits(selected ? .isSelected : [])
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
    let model: OverlayModel
    @Binding var layout: WidgetLayout
    @ObservedObject private var drag = sharedDrag

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let grid = Grid.preview(u: 3.2)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
            ForEach(layout.shelf) { widget in
                VStack(spacing: 6) {
                    CardPreview(model: model, widget: widget, size: layout.size(of: widget), style: layout.style(of: widget), grid: grid)
                        .frame(height: grid.h(.large), alignment: .center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(PreviewBackdrop().allowsHitTesting(false))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text(widget.name).font(.callout)
                    Text(layout.size(of: widget).name).font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity)
                .background(shape.fill(Color.primary.opacity(0.05)))
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
        .background(RoundedRectangle(cornerRadius: 16).strokeBorder(drag.overShelf ? Color.graphite : .clear, lineWidth: 2))
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
        guard p.y >= grid.margin, row < grid.rows else { return nil }
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
