import AppKit
import SwiftUI

// MARK: - Palette

/// Colors sampled from the album art: one per region of the cover, plus their average.
struct Palette: Equatable {
    struct RGB: Equatable {
        let r, g, b: Double
        var color: Color { Color(red: r, green: g, blue: b) }
        var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    }

    let colors: [RGB] // 5, one per blob
    let base: RGB

    static let fallback = Palette(colors: [
        RGB(r: 0.30, g: 0.32, b: 0.55), RGB(r: 0.45, g: 0.30, b: 0.55), RGB(r: 0.20, g: 0.40, b: 0.60),
        RGB(r: 0.15, g: 0.18, b: 0.35), RGB(r: 0.40, g: 0.35, b: 0.60),
    ], base: RGB(r: 0.10, g: 0.10, b: 0.18))

    init(colors: [RGB], base: RGB) {
        self.colors = colors
        self.base = base
    }

    /// Shrinks the cover to 3×2 pixels; each pixel is the average of one region.
    init?(image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var px = [UInt8](repeating: 0, count: 3 * 2 * 4)
        let drawn = px.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 12,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: 3, height: 2))
            return true
        }
        guard drawn else { return nil }
        let cells = (0..<6).map { i in
            RGB(r: Double(px[i * 4]) / 255, g: Double(px[i * 4 + 1]) / 255, b: Double(px[i * 4 + 2]) / 255)
        }
        colors = Array(cells.prefix(5))
        base = RGB(r: cells.map(\.r).reduce(0, +) / 6, g: cells.map(\.g).reduce(0, +) / 6, b: cells.map(\.b).reduce(0, +) / 6)
    }

    var luminance: Double { colors.map(\.luminance).reduce(0, +) / Double(colors.count) }
}

// MARK: - Background

/// Time that only runs while music plays, so a paused background freezes and resumes in place.
final class MotionClock: ObservableObject {
    private var banked: TimeInterval = 0
    private var since: Date?

    func time(at date: Date) -> TimeInterval {
        banked + (since.map { date.timeIntervalSince($0) } ?? 0)
    }

    func set(running: Bool) {
        if running, since == nil {
            since = .now
        } else if !running, let since {
            banked += Date.now.timeIntervalSince(since)
            self.since = nil
        }
    }
}

/// Apple Music–style backdrop: the album art itself, in three layers that turn and drift at their own
/// speeds, blurred until only soft colour fields remain, then dimmed.
struct MusicBackground: View {
    let artwork: NSImage?
    let palette: Palette
    let playing: Bool
    @StateObject private var clock = MotionClock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Size (fraction of the field), spin period in s (negative turns the other way),
    /// drift radius (fraction of the field), drift period in s, and a phase so layers don't move in step.
    private static let layers: [(size: Double, spin: Double, drift: Double, driftPeriod: Double, phase: Double)] = [
        (1.25, 90, 0.08, 41, 0),
        (0.90, -63, 0.20, 29, 2.1),
        (0.65, 47, 0.26, 37, 4.2),
    ]

    var body: some View {
        GeometryReader { geo in
            // Larger than the screen's diagonal so no corner ever shows.
            let side = hypot(geo.size.width, geo.size.height) * 1.1
            // Drawn small, blurred, then scaled up: smooth, no banding, cheap to animate at full frame rate.
            let small: CGFloat = 128
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion)) { context in
                let t = reduceMotion ? 0 : clock.time(at: context.date)
                ZStack {
                    palette.base.color
                    ForEach(0..<Self.layers.count, id: \.self) { i in layer(i, t: t, small: small) }
                }
                .frame(width: small, height: small)
                .blur(radius: small * 0.13, opaque: true)
                .saturation(1.25)
                .drawingGroup()
                .scaleEffect(side / small)
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .overlay(shade)
            .clipped()
        }
        .animation(.easeInOut(duration: 1.4), value: palette)
        .onChange(of: playing, initial: true) { clock.set(running: playing) }
    }

    private func layer(_ i: Int, t: TimeInterval, small: CGFloat) -> some View {
        let l = Self.layers[i]
        let a = t / l.driftPeriod * 2 * .pi + l.phase
        let size = small * l.size
        return Group {
            if let artwork {
                Image(nsImage: artwork).resizable().interpolation(.medium)
            } else {
                AngularGradient(colors: palette.colors.map(\.color) + [palette.colors[0].color], center: .center)
            }
        }
        .frame(width: size, height: size)
        .rotationEffect(.radians(t / l.spin * 2 * .pi))
        .offset(x: cos(a) * l.drift * small, y: sin(a * 0.8) * l.drift * small)
    }

    /// Darker on the left; bright covers get a stronger shade so white text stays readable.
    /// Includes a flat 0.3 black (Apple's backdrop sits well below the cover's brightness): two black
    /// layers a and b composite to 1-(1-a)(1-b), so each stop is 0.3 + 0.7 * its own alpha.
    private var shade: some View {
        let k = palette.luminance > 0.5 ? 1.7 : 1
        return LinearGradient(stops: [
            .init(color: .black.opacity(0.3 + 0.7 * min(0.6, 0.3 * k)), location: 0),
            .init(color: .black.opacity(0.3 + 0.7 * min(0.4, 0.1 * k)), location: 0.6),
            .init(color: .black.opacity(0.3 + 0.7 * min(0.45, 0.15 * k)), location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }
}
