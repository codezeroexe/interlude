import AppKit
import CoreText
import os
import SwiftUI

/// Card material, chosen in Settings.
enum GlassStyle: String, CaseIterable {
    static let key = "glassStyle"
    static let frostKey = "glassFrost"               // 0 = barely blurred, 1 = heavily frosted
    static let transparencyKey = "glassTransparency" // 0 = most solid, 1 = most see-through
    static let tintKey = "glassTint2"                // extra dark tint: 0 = none, 1 = darkest
    static let defaultFrost = 0.5
    static let defaultTransparency = 0.7
    static let defaultTint = 0.0
    /// Liquid Glass tint: "dark" or "light".
    static let liquidToneKey = "liquidTone"

    /// Blurred wallpaper with no rim: the original Interlude look.
    case frosted
    /// Apple's Liquid Glass, as on macOS and iPadOS widgets: refracting, with a light rim.
    case liquid

    var name: String {
        switch self {
        case .frosted: "Frosted"
        case .liquid: "Liquid Glass"
        }
    }
}

/// Clock typeface, chosen in Settings. Date and weather always use DM Mono.
enum ClockFont: String, CaseIterable {
    static let key = "clockFont"
    case sfPro
    case instrumentSerif

    var name: String {
        switch self {
        case .sfPro: "Apple"
        case .instrumentSerif: "Serif"
        }
    }

    /// Registers the fonts shipped in the app bundle (Instrument Serif, DM Mono) for this process.
    static func registerBundledFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

/// Draws a card's glass background in the chosen style, frost and transparency.
struct GlassModifier: ViewModifier {
    let radius: CGFloat
    let shadowRadius: CGFloat
    let shadowY: CGFloat
    @AppStorage(GlassStyle.key) private var style = GlassStyle.frosted
    @AppStorage(GlassStyle.frostKey) private var frost = GlassStyle.defaultFrost
    @AppStorage(GlassStyle.transparencyKey) private var transparency = GlassStyle.defaultTransparency
    @AppStorage(GlassStyle.tintKey) private var tint = GlassStyle.defaultTint
    @Environment(\.plainCards) private var plain
    @Environment(\.frostBackdrop) private var backdrop
    @AppStorage(GlassStyle.liquidToneKey) private var liquidTone = "dark"

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if plain {
            drawn(content, shape)
        } else {
            styled(content, shape)
        }
    }

    /// Off screen, system blur and Liquid Glass don't draw. This draws the same look by hand: a blurred
    /// copy of the wallpaper still behind the card (when there is one), the tint and, for Liquid Glass, the rim.
    private func drawn(_ content: Content, _ shape: RoundedRectangle) -> some View {
        let u = shadowRadius / 2.5
        let liquid = style == .liquid
        return content.background {
            ZStack {
                if let backdrop, let still = PreviewBackdrop.image {
                    GeometryReader { geo in
                        let frame = geo.frame(in: .named(FrostBackdrop.space))
                        // The still is pre-blurred, since window captures drop SwiftUI blurs.
                        let shown = max(backdrop.width / still.size.width, backdrop.height / still.size.height)
                        Image(nsImage: PreviewBackdrop.blurred((liquid ? 14 : 4 + 76 * frost) * u / 14 / shown))
                            .resizable().scaledToFill()
                            .frame(width: backdrop.width, height: backdrop.height)
                            .clipped()
                            .offset(x: -frame.minX, y: -frame.minY)
                    }
                }
                if liquid {
                    shape.fill(liquidTone == "light" ? Color.white.opacity(0.14) : Color.black.opacity(0.32))
                } else {
                    shape.fill(Color(white: 0.1).opacity(0.7 * (1 - transparency)))
                    shape.fill(.white.opacity(0.06))
                    shape.fill(.black.opacity(0.6 * tint))
                }
            }
            .clipShape(shape)
            .overlay {
                if liquid {
                    shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.06), .white.opacity(0.22)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing),
                                       lineWidth: max(1, 0.09 * u))
                }
            }
            .background(shape.fill(.black.opacity(0.01)).shadow(color: .black.opacity(0.22), radius: shadowRadius, y: shadowY))
        }
    }

    @ViewBuilder private func styled(_ content: Content, _ shape: RoundedRectangle) -> some View {
        switch style {
        case .frosted:
            content.background {
                ZStack {
                    // Frost: how blurred the wallpaper behind is. Transparency: how much of it shows
                    // through a dark fill. Tint: an extra dark layer on top.
                    FrostView(radius: 4 + 76 * frost, cornerRadius: radius)
                    shape.fill(Color(white: 0.1).opacity(0.7 * (1 - transparency)))
                    shape.fill(.white.opacity(0.06))
                    shape.fill(.black.opacity(0.6 * tint))
                }
                .clipShape(shape)
                .background(shape.fill(.black.opacity(0.01)).shadow(color: .black.opacity(0.22), radius: shadowRadius, y: shadowY))
            }
        case .liquid:
            if #available(macOS 26, *) {
                // Apple's standard glass, which follows the system's Liquid Glass setting (System Settings ›
                // Appearance). Light is the glass as it comes; Dark tints it black so it reads as smoked glass.
                content.glassEffect(liquidTone == "light" ? .regular : .regular.tint(.black.opacity(0.45)), in: shape)
            } else {
                content.background(.thinMaterial, in: shape)
            }
        }
    }
}

extension View {
    /// Card background in the glass style picked in Settings.
    func glass(_ grid: Grid, capsule: Bool = false) -> some View {
        modifier(GlassModifier(radius: capsule ? 100 : grid.radius, shadowRadius: 2.5 * grid.u, shadowY: 0.8 * grid.u))
    }
}

// MARK: - Frost

/// A blur of whatever is behind it in the window, with an adjustable radius and no tint of its own.
/// Built on the system's visual-effect view: its blur radius isn't public, so this sets the radius on
/// the blur layer directly and hides the system tint. If a macOS update changes those layers, it falls
/// back to the normal system blur.
struct FrostView: NSViewRepresentable {
    let radius: CGFloat
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> FrostNSView {
        let view = FrostNSView()
        view.blendingMode = .withinWindow
        view.material = .fullScreenUI
        view.state = .active
        return view
    }

    func updateNSView(_ view: FrostNSView, context: Context) {
        view.blurRadius = radius
        view.cornerRadius = cornerRadius
    }
}

final class FrostNSView: NSVisualEffectView {
    private static let log = Logger(subsystem: "com.hari.Interlude", category: "frost")
    nonisolated(unsafe) private static var loggedLayers = false

    var blurRadius: CGFloat = 30 { didSet { if blurRadius != oldValue { applyBlur() } } }
    var cornerRadius: CGFloat = 0 { didSet { if cornerRadius != oldValue { needsLayout = true } } }
    private var maskedRadius: CGFloat = -1

    override func layout() {
        super.layout()
        // Rounded corners: a stretchable mask image, as Apple recommends for visual-effect views.
        let r = min(cornerRadius, bounds.height / 2, bounds.width / 2)
        if r != maskedRadius, r > 0 {
            maskedRadius = r
            let image = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
                NSColor.black.setFill()
                NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
                return true
            }
            image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
            image.resizingMode = .stretch
            maskImage = image
        }
        applyBlur()
    }

    override func updateLayer() {
        super.updateLayer()
        applyBlur()
    }

    private func applyBlur() {
        guard let layer else { return }
        let all = Self.flatten(layer)
        if !Self.loggedLayers, !all.isEmpty {
            Self.loggedLayers = true
            Self.log.notice("layers: \(all.map { "\(type(of: $0)) \(($0.filters ?? []).map { "\($0)" })" }, privacy: .public)")
        }
        let backdrops = all.filter { String(describing: type(of: $0)).contains("Backdrop") }
        guard !backdrops.isEmpty else { return }
        for backdrop in backdrops {
            backdrop.setValue(blurRadius, forKeyPath: "filters.gaussianBlur.inputRadius")
        }
        // Hide the material's own tint and noise layers; GlassModifier draws its own tint.
        for sublayer in all where !backdrops.contains(sublayer) && sublayer !== layer && sublayer.sublayers == nil {
            sublayer.opacity = 0
        }
    }

    private static func flatten(_ layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(flatten)
    }
}

/// Marks a view as the frame of a wallpaper still, so plain cards inside it can blur their own copy of it.
enum FrostBackdrop {
    static let space = "frostBackdrop"
}

private struct FrostBackdropKey: EnvironmentKey {
    static let defaultValue: CGSize? = nil
}

extension View {
    /// This view is a wallpaper still's frame, of `size`. Plain cards inside it blur that still.
    func frostBackdrop(_ size: CGSize?) -> some View {
        environment(\.frostBackdrop, size).coordinateSpace(name: FrostBackdrop.space)
    }

    /// The same, for a view filling the space it's offered.
    func frostBackdrop(_ on: Bool = true) -> some View {
        GeometryReader { geo in
            frame(width: geo.size.width, height: geo.size.height).frostBackdrop(on ? geo.size : nil)
        }
    }
}

private struct PlainCardsKey: EnvironmentKey {
    static let defaultValue = false
}

private struct PreviewMusicKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ClockFontOverrideKey: EnvironmentKey {
    static let defaultValue: ClockFont? = nil
}

extension EnvironmentValues {
    /// A clock font for previews that shouldn't follow Settings, like the welcome window's serif clock.
    var clockFontOverride: ClockFont? {
        get { self[ClockFontOverrideKey.self] }
        set { self[ClockFontOverrideKey.self] = newValue }
    }

    /// Settings previews: act as if music is playing, so "Match Music" colours show even when paused.
    var previewMusic: Bool {
        get { self[PreviewMusicKey.self] }
        set { self[PreviewMusicKey.self] = newValue }
    }

    /// The size of the wallpaper still behind the cards, in `FrostBackdrop.space`.
    var frostBackdrop: CGSize? {
        get { self[FrostBackdropKey.self] }
        set { self[FrostBackdropKey.self] = newValue }
    }

    /// Off-screen rendering can't draw glass, so cards draw it by hand instead.
    var plainCards: Bool {
        get { self[PlainCardsKey.self] }
        set { self[PlainCardsKey.self] = newValue }
    }
}
