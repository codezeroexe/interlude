import SwiftUI

/// Artwork, title, artist and Mac-style controls. No seek bar in any style.
/// Small: fade, pill, thumbnail. Medium: classic, fade, pill. Large: fade, panel.
struct NowPlayingCard: View {
    @ObservedObject var nowPlaying: NowPlaying
    let grid: Grid
    var size: WidgetSize = .medium
    var style = 0

    /// Nothing playing, or paused for over 5 minutes: the card stays, saying so.
    private var idle: Bool { !nowPlaying.visible }
    /// Idle but a player still holds a track (paused a while), so Space and play can resume it.
    private var resumable: Bool { idle && nowPlaying.track != nil }

    var body: some View {
        let track = idle ? Track.idle : nowPlaying.track!
        let shape = RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
        content(track)
            .animation(.easeInOut(duration: 0.6), value: track.id)
            .frame(width: grid.w(size), height: grid.h(size))
            .clipShape(shape) // covers that fill the card stop at its rounded edge
            .glass(grid)
    }

    @ViewBuilder private func content(_ track: Track) -> some View {
        let u = grid.u
        switch (size, style) {
        case (.small, 1):
            ZStack(alignment: .bottom) {
                cover
                controls(track, 1.6).padding(.horizontal, 1.4 * u).padding(.vertical, 0.8 * u).glass(grid, capsule: true)
                    .padding(1 * u)
            }
        case (.small, 2):
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    artwork.frame(width: 6 * u, height: 6 * u)
                        .clipShape(RoundedRectangle(cornerRadius: 1.2 * u, style: .continuous))
                    Spacer()
                    Image(systemName: "music.note").font(.system(size: 1.6 * u))
                }
                titles(track, title: 1.6, artist: 1.3, label: false).padding(.top, 1 * u)
                Spacer(minLength: 0)
                HStack { control("backward.fill", .previous); Spacer(); playPause(track); Spacer(); control("forward.fill", .next) }
                    .font(.system(size: 1.9 * u))
            }
            .padding(1.6 * u)
        case (.small, _), (.large, 0):
            let big = size == .large
            ZStack(alignment: .bottom) {
                cover.mask(LinearGradient(stops: [.init(color: .black, location: 0.35), .init(color: .clear, location: 0.92)],
                                          startPoint: .top, endPoint: .bottom))
                VStack(spacing: 0.3 * u) {
                    centred(track, title: big ? 2.4 : 1.7, artist: big ? 1.6 : 1.3, hint: resumable && big)
                    controls(track, big ? 2 : 1.5).padding(.top, (big ? 1.2 : 0.7) * u)
                }
                .padding((big ? 2.2 : 1.4) * u)
            }
        case (.large, _):
            ZStack(alignment: .bottom) {
                cover
                VStack(spacing: 1 * u) {
                    centred(track, title: 2, artist: 1.6, hint: resumable)
                    controls(track, 2)
                }
                .padding(1.6 * u)
                .frame(maxWidth: .infinity)
                .glass(grid)
                .padding(1.6 * u)
            }
        case (.medium, 1):
            HStack(spacing: 0) {
                Color.clear.frame(width: 1.1 * grid.s, height: grid.s).overlay { artwork }.clipped()
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                         startPoint: .leading, endPoint: .trailing))
                classicText(track).padding(1.8 * u).padding(.leading, -3 * u)
            }
        case (.medium, 2):
            ZStack(alignment: .bottom) {
                cover
                HStack(spacing: 1.2 * u) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(track.title).font(.system(size: 1.6 * u, weight: .semibold))
                        Text(track.artist).font(.system(size: 1.3 * u)).opacity(0.75)
                    }
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    controls(track, 1.6)
                }
                .padding(.leading, 2 * u)
                .padding(.trailing, 1.4 * u)
                .padding(.vertical, 0.9 * u)
                .glass(grid, capsule: true)
                .padding(1.2 * u)
            }
        default:
            let art = grid.s - 3.6 * u
            HStack(spacing: 2 * u) {
                artwork.frame(width: art, height: art)
                    .clipShape(RoundedRectangle(cornerRadius: 1.8 * u, style: .continuous))
                classicText(track)
            }
            .padding(1.8 * u)
        }
    }

    /// Controls top right; "NOW PLAYING", title and artist bottom left.
    private func classicText(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            titles(track, title: 2.4, artist: 2.1, label: !idle, hint: resumable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { controls(track, 2.2) }
    }

    private func titles(_ track: Track, title: CGFloat, artist: CGFloat, label: Bool, hint: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if label {
                Text("NOW PLAYING")
                    .font(.system(size: 1.35 * grid.u, weight: .semibold))
                    .tracking(0.08 * grid.u)
                    .opacity(0.55)
                    .padding(.bottom, 0.3 * grid.u)
            }
            Marquee(text: track.title, u: grid.u).font(.system(size: title * grid.u, weight: .semibold))
            Marquee(text: track.artist, u: grid.u).font(.system(size: artist * grid.u)).opacity(0.8)
            if hint { spaceHint(artist * 0.6) }
        }
    }

    /// Only in the idle state: Space starts the player from the overlay.
    private func spaceHint(_ points: CGFloat) -> some View {
        Text("Press Space to play").font(.system(size: points * grid.u)).opacity(0.55).lineLimit(1)
            .transition(.opacity)
    }

    private func centred(_ track: Track, title: CGFloat, artist: CGFloat, hint: Bool = false) -> some View {
        VStack(spacing: 0.1 * grid.u) {
            Text(track.title).font(.system(size: title * grid.u, weight: .semibold))
            Text(track.artist).font(.system(size: artist * grid.u)).opacity(0.75)
            if hint { spaceHint(artist * 0.7) }
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
    }

    /// The cover filling the card.
    private var cover: some View {
        // Overlay on a clear fill, so a square cover on a wide card is cropped, not stretching the card.
        Color.clear.overlay { artwork }.clipped()
    }

    /// When on, the cover is printed into the glass: it keeps only its light and dark, and the glass
    /// shows through it a little, like the other cards.
    @AppStorage("monochromeArtwork") private var monochrome = true

    @ViewBuilder private var artwork: some View {
        Group {
            if !idle, let image = nowPlaying.artwork {
                Image(nsImage: image).resizable().scaledToFill()
                    // Plain grey, not a luminosity blend: a blend skips the glass and lets the sharp
                    // video show through a cover's dark areas.
                    .grayscale(monochrome ? 1 : 0)
                    .opacity(monochrome ? 0.4 : 1)
                    .animation(.smooth(duration: 0.6), value: monochrome)
            } else {
                Rectangle().fill(.white.opacity(0.12))
                    .overlay { Image(systemName: "music.note").font(.system(size: 4 * grid.u)).opacity(0.6) }
            }
        }
        .id(nowPlaying.artwork.map(ObjectIdentifier.init)) // crossfade when the cover itself changes
        .transition(.opacity)
    }

    /// Plain symbols, no circles behind them.
    private func controls(_ track: Track, _ points: CGFloat) -> some View {
        HStack(spacing: points * 0.6 * grid.u) {
            control("backward.fill", .previous)
            playPause(track)
            control("forward.fill", .next)
        }
        .font(.system(size: points * grid.u))
    }

    private func playPause(_ track: Track) -> some View {
        control(track.playing ? "pause.fill" : "play.fill", .playPause)
    }

    private func control(_ symbol: String, _ command: NowPlaying.Command) -> some View {
        // Idle: previous/next do nothing; play/pause works only while a player still holds a track.
        let dead = idle && (command != .playPause || !resumable)
        return Button { nowPlaying.send(command) } label: {
            Image(systemName: symbol).contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(dead)
        .opacity(dead ? 0.3 : idle ? 0.85 : 1)
        .animation(.smooth(duration: 0.3), value: idle)
    }
}

final class HoverState: ObservableObject {

    @Published var on = false
}

/// One line of text. When too long to fit, it pauses, then scrolls left in a continuous loop
/// (a second copy follows the first), with both edges fading out instead of hard clipping.
struct Marquee: View {
    let text: String
    let u: CGFloat
    @StateObject private var size = MarqueeSize()
    @Environment(\.font) private var font

    var body: some View {
        let overflow = size.text > size.box + 0.5
        // Overflow: Core Animation scrolls two pre-rendered copies in the render server, so SwiftUI never re-lays-out per frame.
        // The label stays (invisible) to measure text and box; the layer view draws on top of it.
        label
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading) // minWidth 0: long text must not widen the card
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { size.box = $0 }
            .opacity(overflow ? 0 : 1)
            .overlay {
                if overflow {
                    MarqueeLayerView(text: text, font: font, color: .white, u: u, textWidth: size.text, start: size.start)
                }
            }
    }

    private var label: some View {
        Text(text)
            .lineLimit(1)
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if width != size.text { size.text = width; size.start = .now } // new text restarts the loop
            }
    }

    /// Holds for `hold` seconds, then moves `distance` points at `speed`, then repeats.
    /// At the end the second copy sits exactly where the first started, so the loop is seamless.
    static func offset(at time: TimeInterval, distance: CGFloat, speed: CGFloat, hold: TimeInterval = 2.5) -> CGFloat {
        let cycle = hold + distance / speed
        let local = max(0, time).truncatingRemainder(dividingBy: cycle)
        return max(0, local - hold) * speed
    }
}

final class MarqueeSize: ObservableObject {
    @Published var text: CGFloat = 0
    @Published var box: CGFloat = 0
    var start = Date.now
}

/// The overflowing marquee: the label is rendered to an image once, and two copies scroll via CAKeyframeAnimation.
/// Same timing as `Marquee.offset`, same edge fades (left fade animated on the mask's first stop).
private struct MarqueeLayerView: NSViewRepresentable {
    let text: String
    let font: Font?
    let color: Color
    let u: CGFloat
    let textWidth: CGFloat
    let start: Date

    func makeNSView(context: Context) -> MarqueeNSView { MarqueeNSView() }
    func updateNSView(_ view: MarqueeNSView, context: Context) { view.config = self }
    static func dismantleNSView(_ view: MarqueeNSView, coordinator: ()) { view.stop() }
}

private final class MarqueeNSView: NSView {
    var config: MarqueeLayerView? { didSet { refresh() } }
    private let content = CALayer(), copyA = CALayer(), copyB = CALayer(), fade = CAGradientLayer()
    private var rendered: (text: String, font: Font?, color: Color, scale: CGFloat)?
    private var size = CGSize.zero
    private var animated: (start: Date, u: CGFloat, width: CGFloat, box: CGSize)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.mask = fade
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(content)
        content.addSublayer(copyA)
        content.addSublayer(copyB)
    }
    required init?(coder: NSCoder) { nil }

    func stop() { content.removeAllAnimations(); fade.removeAllAnimations(); animated = nil }
    override func layout() { super.layout(); refresh() }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); refresh() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); refresh() }

    private func refresh() {
        guard let c = config, bounds.width > 0, bounds.height > 0, c.textWidth > 0 else { return }
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        if rendered?.text != c.text || rendered?.font != c.font || rendered?.color != c.color || rendered?.scale != scale {
            let renderer = ImageRenderer(content: Text(c.text).font(c.font).foregroundStyle(c.color)
                .lineLimit(1).fixedSize().environment(\.colorScheme, .dark))
            renderer.scale = scale
            guard let image = renderer.cgImage else { return }
            rendered = (c.text, c.font, c.color, scale)
            size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            for l in [copyA, copyB] { l.contents = image; l.contentsScale = scale; l.contentsGravity = .topLeft }
            animated = nil
        }

        let gap = 4 * c.u, fadeW = 2 * c.u, speed = 2.5 * c.u, hold = 2.5
        let distance = c.textWidth + gap
        content.frame = bounds
        copyA.frame = CGRect(x: 0, y: bounds.height - size.height, width: size.width, height: size.height)
        copyB.frame = copyA.frame.offsetBy(dx: c.textWidth + gap, dy: 0)
        fade.frame = bounds
        let edge = fadeW / bounds.width
        fade.locations = [0, edge, 1 - edge, 1].map { NSNumber(value: $0) }

        if let a = animated, a.start == c.start, a.u == c.u, a.width == c.textWidth, a.box == bounds.size { return }
        animated = (c.start, c.u, c.textWidth, bounds.size)
        let move = distance / speed, cycle = hold + move, ramp = fadeW / speed
        let begin = CACurrentMediaTime() - Date.now.timeIntervalSince(c.start)

        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        slide.values = [0, 0, -distance]
        slide.keyTimes = [0, hold / cycle, 1].map { NSNumber(value: $0) }
        let dim = CAKeyframeAnimation(keyPath: "colors")
        let on = [CGColor.black, .black, .black, .clear], off = [CGColor(gray: 0, alpha: 0), .black, .black, .clear]
        dim.values = [on, on, off, off, on]
        dim.keyTimes = [0, hold, hold + ramp, cycle - ramp, cycle].map { NSNumber(value: $0 / cycle) }
        for (anim, layer) in [(slide, content), (dim, fade)] as [(CAKeyframeAnimation, CALayer)] {
            anim.calculationMode = .linear
            anim.duration = cycle
            anim.repeatCount = .infinity
            anim.beginTime = begin
            layer.add(anim, forKey: "marquee")
        }
        fade.colors = on
    }
}
