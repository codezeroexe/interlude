import SwiftUI

/// The welcome window on first launch, as in reference/settings-onboarding.html: a live picture of the
/// standby screen built from the real cards, then five short steps. Every step can be skipped;
/// closing the window counts as done. Settings › Privacy can show it again.
struct OnboardingView: View {
    static let windowID = "welcome"
    static let doneKey = "onboarded"
    private static let lastStep = 4

    let overlay: OverlayController
    @StateObject private var flow: OnboardingFlow
    @AppStorage(doneKey) private var done = false
    @AppStorage(IdleMonitor.minutesKey) private var idleMinutes = IdleMonitor.defaultMinutes
    @StateObject private var login = LoginItem()
    @StateObject private var permissions: PermissionsModel
    @Environment(\.dismissWindow) private var dismissWindow

    init(overlay: OverlayController, step: Int = 0) {
        self.overlay = overlay
        _flow = StateObject(wrappedValue: OnboardingFlow(step: step))
        _permissions = StateObject(wrappedValue: PermissionsModel(model: overlay.model))
    }

    var body: some View {
        VStack(spacing: 0) {
            StandbyScene(model: overlay.demo, cards: flow.step == Self.lastStep ? [] : flow.starter.cards)
                .frame(height: 260)
                .environment(\.clockFontOverride, .instrumentSerif)
                .overlay(alignment: .topTrailing) {
                    if flow.step == Self.lastStep {
                        MenuPreview()
                            .padding(.top, 30)
                            .padding(.trailing, 40)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topTrailing)))
                    }
                }
                // Fades into the window, whatever its material shows.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.6), .init(color: .black.opacity(0.4), location: 0.82), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))

            content
                .id(flow.step)
                .transition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(height: 290, alignment: .center)
                .padding(.horizontal, 48)
                .padding(.top, 4)

            footer
        }
        .frame(width: 720)
        .ignoresSafeArea()
        .toggleStyle(GraphiteSwitch())
        .containerBackground(.thickMaterial, for: .window)
        .animation(.smooth(duration: 0.35), value: flow.step)
        .animation(.smooth(duration: 0.35), value: flow.starter)
        .onAppear {
            NSApp.activate() // menu bar apps don't come forward on their own
            overlay.model.nowPlaying.start()
            permissions.reload()
        }
        .onDisappear {
            overlay.model.nowPlaying.stop()
            done = true // closing the window counts as skipping; it won't open on its own again
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in permissions.reload() }
    }

    @ViewBuilder private var content: some View {
        switch flow.step {
        case 0:
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .shadow(color: .black.opacity(0.35), radius: 10, y: 8)
                    .padding(.top, -44)
                    .accessibilityHidden(true)
                title("Welcome to Interlude")
                lead("When your Mac sits idle, Interlude turns the screen into a calm glance at the time, your day and what's playing.")
            }
        case 1:
            VStack(spacing: 8) {
                title("Choose when it appears")
                lead("Interlude starts after your Mac has been idle for a while. Move the mouse or press a key to get back to work.")
                HStack(spacing: 22) {
                    HStack(spacing: 8) {
                        Text("Start after")
                        Segmented(selection: $idleMinutes, choices: [2, 5, 10, 15].map { Choice("\($0) min", $0) })
                    }
                    HStack(spacing: 8) {
                        Toggle("Open at login", isOn: $login.enabled).labelsHidden()
                        Text("Open at login").accessibilityHidden(true)
                    }
                }
                .padding(.top, 22)
            }
        case 2:
            VStack(spacing: 8) {
                title("Pick a starting layout")
                lead("You can move, resize and swap any card later in Settings.")
                HStack(spacing: 12) {
                    ForEach(StarterLayout.allCases, id: \.self) { starterButton($0) }
                }
                .padding(.top, 20)
            }
        case 3:
            VStack(spacing: 8) {
                title("Allow what you want to see")
                lead("Each card works without the others. Skip any you don't need.")
                SettingsGroup {
                    ForEach(permissions.items) { item in
                        PermissionRow(item: item) { permissions.fix(item.id) }
                    }
                }
                .frame(maxWidth: 500)
                .padding(.top, 10)
            }
        default:
            VStack(spacing: 8) {
                title("Find it in the menu bar")
                lead("Start Interlude whenever you like, change when it starts, or open Settings from the icon at the top of your screen.")
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                ForEach(0...Self.lastStep, id: \.self) { i in
                    Capsule()
                        .fill(i == flow.step ? Color.primary : Color.primary.opacity(0.15))
                        .frame(width: i == flow.step ? 20 : 7, height: 7)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(flow.step + 1) of \(Self.lastStep + 1)")
            Spacer()
            if (1..<Self.lastStep).contains(flow.step) {
                Button("Set Up Later") { flow.step = Self.lastStep }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 6)
            }
            Button("Back") { flow.step -= 1 }
                .buttonStyle(.capsule)
                .opacity(flow.step > 0 ? 1 : 0)
                .disabled(flow.step == 0)
            Button(flow.step == 0 ? "Get Started" : flow.step == Self.lastStep ? "Done" : "Continue") {
                if flow.step < Self.lastStep { flow.step += 1 } else { finish() }
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 22)
    }

    private func finish() {
        done = true
        dismissWindow(id: Self.windowID)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 26, weight: .bold))
            .tracking(-0.5)
            .multilineTextAlignment(.center)
    }

    private func lead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 470)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func starterButton(_ option: StarterLayout) -> some View {
        let on = option == flow.starter
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button {
            let previous = flow.starter
            flow.starter = option
            // Only overwrite an empty slot or the last starter we seeded, never a custom layout.
            let key = LayoutProfile.standard.key
            let columns = Grid(size: StartConditions.screen?.frame.size ?? CGSize(width: 1710, height: 1112)).columns
            let saved = UserDefaults.standard.string(forKey: key)
            if saved == nil || saved == previous.layout(columns: columns).rawValue {
                UserDefaults.standard.set(option.layout(columns: columns).rawValue, forKey: key)
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // The same scene as above, drawn large and scaled down so the cards keep their proportions.
                StandbyScene(model: overlay.demo, cards: option.cards)
                    .environment(\.clockFontOverride, .instrumentSerif)
                    .frame(width: 720, height: 260) // the picture above, at its own shape
                    .scaleEffect(160 / 720, anchor: .topLeading)
                    .frame(width: 160, height: 260 * 160 / 720, alignment: .topLeading)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(option.name).fontWeight(.semibold).padding(.top, 7).padding(.horizontal, 4)
                Text(option.detail).font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 4).padding(.bottom, 2)
            }
            .padding(8)
            .frame(width: 176, alignment: .leading)
            .background(shape.fill(Color.groupFill))
            .overlay(shape.strokeBorder(on ? Color.graphite : Color.primary.opacity(0.08), lineWidth: on ? 2.5 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.name): \(option.detail)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Which step the welcome window shows and the layout picked. (A model object: no SwiftUI macros here.)
final class OnboardingFlow: ObservableObject {
    @Published var step: Int
    @Published var starter = StarterLayout.standard
    init(step: Int) { self.step = step }
}

/// Layouts to start from in the welcome window. Each is a normal layout, edited later in Settings.
enum StarterLayout: CaseIterable {
    case bigClock, day, standard

    var name: String {
        switch self {
        case .bigClock: "Minimal"
        case .day: "Your Day"
        case .standard: "At the Desk"
        }
    }

    var detail: String {
        switch self {
        case .bigClock: "Just the clock"
        case .day: "Weather and next event"
        case .standard: "Music, calendar, battery"
        }
    }

    /// The cards the welcome picture shows for this layout, row by row: widget, size, style.
    var cards: [[(Widget, WidgetSize, Int)]] {
        switch self {
        case .bigClock: []
        case .day: [[(.weather, .medium, 0)], [(.calendar, .medium, 0)]]
        case .standard: [[(.nowPlaying, .medium, 0)], [(.calendar, .small, 0), (.battery, .small, 0)]]
        }
    }

    func layout(columns n: Int) -> WidgetLayout {
        let raw = switch self {
        case .standard: ""
        case .day: "\(n)|clock@0,1,L,0;weather@\(n - 2),0,M,0;calendar@\(n - 2),1,M,0;reminders@\(n - 2),2,M,0"
        case .bigClock: "\(n)|clock@0,1,XL,0"
        }
        return WidgetLayout(rawValue: raw) ?? .standard(columns: n)
    }
}

/// The menu bar menu, drawn over the picture on the last step.
private struct MenuPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Interlude").fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.top, 2)
            .padding(.bottom, 8)
            item("Start Interlude Now", "⌘S", highlighted: true)
            item("Start Interlude After", "›")
            item("Settings…", "⌘,")
        }
        .padding(10)
        .frame(width: 250)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.22), lineWidth: 0.5))
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .font(.system(size: 13))
    }

    private func item(_ title: String, _ shortcut: String, highlighted: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(shortcut).opacity(0.6)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(highlighted ? Color.white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
