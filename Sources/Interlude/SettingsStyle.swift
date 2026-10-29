import SwiftUI

// The look shared by Settings and the welcome window, from reference/settings-onboarding.html:
// graphite instead of a colour accent, grouped rows with subtitles, and capsule buttons.

extension Color {
    /// Near-black in light mode, near-white in dark. The app is monochrome, so its accent is too.
    static let graphite = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.925, alpha: 1) : NSColor(red: 0.17, green: 0.17, blue: 0.18, alpha: 1)
    })
    /// Text and knobs on graphite.
    static let onGraphite = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.07, alpha: 1) : .white
    })
    /// Background of a group of rows.
    static let groupFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.06) : NSColor(white: 1, alpha: 0.82)
    })
}

/// Capsule buttons: graphite for the main action, a light grey fill for the rest.
struct CapsuleButtonStyle: ButtonStyle {
    var prominent = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: .medium))
            .lineLimit(1)
            .padding(.horizontal, large ? 22 : 16)
            .padding(.vertical, large ? 9 : 6)
            .foregroundStyle(prominent ? Color.onGraphite : Color.primary)
            .background(Capsule().fill(prominent ? Color.graphite : Color.primary.opacity(0.09)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == CapsuleButtonStyle {
    static var capsule: CapsuleButtonStyle { CapsuleButtonStyle() }
    static var capsuleProminent: CapsuleButtonStyle { CapsuleButtonStyle(prominent: true) }
}

/// A switch in graphite. Still a toggle for VoiceOver and the keyboard.
struct GraphiteSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { withAnimation(.smooth(duration: 0.2)) { configuration.isOn.toggle() } } label: {
            Capsule()
                .fill(configuration.isOn ? Color.graphite : Color.primary.opacity(0.13))
                .frame(width: 38, height: 22)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? Color.onGraphite : .white)
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A scrolling settings pane: groups stacked with even spacing.
struct SettingsPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) { content }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(GraphiteSwitch())
        .tint(.graphite)
    }
}

/// Rows in a rounded box with hairlines between them, an optional title above and note below.
struct SettingsGroup<Content: View>: View {
    var title: String?
    var footer: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
            }
            VStack(spacing: 0) {
                Group(subviews: content) { rows in
                    ForEach(rows.indices, id: \.self) { i in
                        if i > 0 { Divider().padding(.horizontal, 12) }
                        rows[i]
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.groupFill))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            if let footer {
                Text(footer)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
        }
    }
}

/// One setting: its name and what it does on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let control: Control

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(minHeight: 40)
    }
}

/// "✓ Allowed", for a permission that's granted.
struct AllowedLabel: View {
    var body: some View {
        Label("Allowed", systemImage: "checkmark.circle.fill")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
    }
}

/// The standby screen as the mockups draw it: the wallpaper, the big wide Clock card on the left and more
/// real cards stacked on the right. Used as the welcome window's picture, its layout thumbnails, and
/// the banner in Settings › Appearance.
struct StandbyScene: View {
    let model: OverlayModel
    var cards: [[(Widget, WidgetSize, Int)]] = StarterLayout.standard.cards
    /// Draws the scene as night mode does: no wallpaper, every card dimmed to one colour.
    var night: NightTint?

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let grid = Grid.preview(u: h * 0.37 / 20) // a row of cards: 37% of the scene, as in the mockup
            ZStack(alignment: .topLeading) {
                if night == nil {
                    PreviewBackdrop()
                        .frame(width: geo.size.width, height: h)
                        .clipped()
                } else {
                    Color.black
                }
                HStack(alignment: .top, spacing: grid.g) {
                    // The big wide clock, without the digits rolling each time the preview redraws.
                    CardPreview(model: model, widget: .clock, size: .extraLarge, style: 0, grid: grid)
                        .transaction { $0.animation = nil }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: grid.g) {
                        ForEach(cards.indices, id: \.self) { r in
                            HStack(spacing: grid.g) {
                                ForEach(cards[r].indices, id: \.self) { c in
                                    let card = cards[r][c]
                                    CardPreview(model: model, widget: card.0, size: card.1, style: card.2, grid: grid)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, geo.size.width * 0.05)
                .padding(.top, h * 0.12)
                // The same treatment as the standby screen at night.
                .compositingGroup()
                .grayscale(night == nil ? 0 : 1)
                .colorMultiply(night?.color ?? .white)
                .opacity(night == nil ? 1 : 0.7)
            }
            .foregroundStyle(.white)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Preview of the Interlude screen")
    }
}

/// The Settings window's background, as in the mockup: the desktop behind the window, heavily blurred,
/// under a smoky tint. Also sets the window up for it: see-through, with a transparent title bar whose
/// close, minimise and zoom buttons sit in a 52-point band, level with the toolbar row.
struct SeeThroughWindow: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            BehindWindowBlur()
            // Mockup: rgba(36,36,40,.82) dark, rgba(246,246,248,.86) light, over a 50px blur. The system
            // blur already tints a little, so these are lighter to land on the same see-through look.
            scheme == .dark
                ? Color(red: 0.14, green: 0.14, blue: 0.157).opacity(0.6)
                : Color(red: 0.965, green: 0.965, blue: 0.973).opacity(0.62)
        }
    }
}

private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowSetupView {
        let view = WindowSetupView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ view: WindowSetupView, context: Context) {}
}

final class WindowSetupView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        // An empty unified toolbar makes the title bar 52 points tall and centres the window buttons in it,
        // the way sidebar apps on macOS line them up.
        if window.toolbar == nil {
            window.toolbar = NSToolbar(identifier: "settings")
            window.toolbarStyle = .unified
        }
        window.toolbar?.showsBaselineSeparator = false
        window.invalidateShadow()
    }
}

// MARK: - Controls drawn as in the mockup

/// One entry in a pop-up menu or segmented control. A choice with no value is a section heading.
struct Choice<Value: Hashable> {
    let title: String
    let value: Value?

    init(_ title: String, _ value: Value) { self.title = title; self.value = value }
    private init(heading: String) { title = heading; value = nil }
    static func heading(_ title: String) -> Choice { Choice(heading: title) }
}

/// The mockup's pop-up button: a soft grey rounded box with the choice and small up-down chevrons.
/// Clicking opens a normal menu with the current choice under the pointer, as a native pop-up does.
struct PopupMenu<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [Choice<Value>]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            Button { open(at: geo.frame(in: .global)) } label: { label }
                .buttonStyle(.plain)
        }
        .frame(width: labelWidth, height: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(current)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open(at: .zero) }
    }

    private var current: String { choices.first { $0.value == selection }?.title ?? "" }

    /// Wide enough for the current choice plus the chevrons.
    private var labelWidth: CGFloat {
        let text = (current as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        return ceil(text) + 36
    }

    private var label: some View {
        HStack(spacing: 0) {
            Text(current).lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(white: 0.53))
        }
        .font(.system(size: 13))
        .padding(.leading, 10)
        .padding(.trailing, 9)
        .frame(width: labelWidth, height: 22)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(scheme == .dark ? Color.white.opacity(0.13) : Color.black.opacity(0.09)))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func open(at frame: CGRect) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let target = MenuTarget()
        var selected: NSMenuItem?
        for choice in choices {
            guard let value = choice.value else {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                menu.addItem(NSMenuItem.sectionHeader(title: choice.title))
                continue
            }
            let item = NSMenuItem(title: choice.title, action: #selector(MenuTarget.pick(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = { selection = value } as () -> Void
            if value == selection { item.state = .on; selected = item }
            menu.addItem(item)
        }
        // NSHostingView is flipped, so its top-left matches SwiftUI's global frame.
        guard let view = NSApp.keyWindow?.contentView else { return }
        withExtendedLifetime(target) {
            menu.popUp(positioning: selected, at: NSPoint(x: frame.minX, y: frame.minY + 1), in: view)
        }
    }
}

private final class MenuTarget: NSObject {
    @objc func pick(_ item: NSMenuItem) { (item.representedObject as? () -> Void)?() }
}

/// The mockup's segmented control: a grey track with the chosen segment raised in a lighter pill.
struct Segmented<Value: Hashable>: View {
    @Binding var selection: Value
    let choices: [Choice<Value>]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(choices.indices, id: \.self) { i in
                let choice = choices[i]
                let on = choice.value == selection
                Button { if let v = choice.value { withAnimation(.smooth(duration: 0.2)) { selection = v } } } label: {
                    Text(choice.title)
                        .font(.system(size: 13, weight: on ? .medium : .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(scheme == .dark ? Color.white.opacity(0.18) : Color.white.opacity(0.82))
                                    .shadow(color: .black.opacity(0.14), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.05)))
        .fixedSize()
    }
}

/// A 0…1 slider in graphite: a thin track, filled up to a round white knob.
struct GraphiteSlider: View {
    let title: String
    @Binding var value: Double

    var body: some View {
        GeometryReader { geo in
            let knob: CGFloat = 18
            let travel = geo.size.width - knob
            let x = travel * value
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4)
                Capsule().fill(Color.graphite).frame(width: x + knob / 2, height: 4)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(1, max(0, (drag.location.x - knob / 2) / travel))
            })
        }
        .frame(width: 180, height: 22)
        .accessibilityRepresentation { Slider(value: $value, in: 0...1) { Text(title) } }
    }
}
