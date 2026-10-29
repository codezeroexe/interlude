import SwiftUI

/// Artwork, title, artist and Mac-style controls. No seek bar in any style.
/// Small: fade, pill, thumbnail. Medium: classic, fade, pill. Large: fade, panel.
struct NowPlayingCard: View {
    @ObservedObject var nowPlaying: NowPlaying
    let grid: Grid
    var size: WidgetSize = .medium
    var style = 0

    var body: some View {
        if let track = nowPlaying.track {
            let shape = RoundedRectangle(cornerRadius: grid.radius, style: .continuous)
            content(track)
                .animation(.easeInOut(duration: 0.6), value: track.id)
                .frame(width: grid.w(size), height: grid.h(size))
                .clipShape(shape) // covers that fill the card stop at its rounded edge
                .glass(grid)
        }
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
                    centred(track, title: big ? 2.4 : 1.7, artist: big ? 1.6 : 1.3)
                    controls(track, big ? 2 : 1.5).padding(.top, (big ? 1.2 : 0.7) * u)
                }
                .padding((big ? 2.2 : 1.4) * u)
            }
        case (.large, _):
            ZStack(alignment: .bottom) {
                cover
                VStack(spacing: 1 * u) {
                    centred(track, title: 2, artist: 1.6)
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
            titles(track, title: 2.4, artist: 2.1, label: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { controls(track, 2.2) }
    }

    private func titles(_ track: Track, title: CGFloat, artist: CGFloat, label: Bool) -> some View {
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
        }
    }

    private func centred(_ track: Track, title: CGFloat, artist: CGFloat) -> some View {
        VStack(spacing: 0.1 * grid.u) {
            Text(track.title).font(.system(size: title * grid.u, weight: .semibold))
            Text(track.artist).font(.system(size: artist * grid.u)).opacity(0.75)
        }
        .lineLimit(1)
        .multilineTextAlignment(.center)
    }

    /// The cover filling the card.
    private var cover: some View {
        // Overlay on a clear fill, so a square cover on a wide card is cropped, not stretching the card.
        Color.clear.overlay { artwork }.clipped()
    }

    /// When on, the cover is printed into the glass: it keeps only its light and dark, takes its colour
    /// from the wallpaper behind (luminosity blend), and lets that show through, like the other cards.
    @AppStorage("monochromeArtwork") private var monochrome = true

    @ViewBuilder private var artwork: some View {
        Group {
            if let image = nowPlaying.artwork {
                Image(nsImage: image).resizable().scaledToFill()
                    .blendMode(monochrome ? .luminosity : .normal)
                    .opacity(monochrome ? 0.6 : 1)
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
        Button { nowPlaying.send(command) } label: {
            Image(systemName: symbol).contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
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

    var body: some View {
        let gap = 4 * u
        let fade = 2 * u
        let overflow = size.text > size.box + 0.5
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !overflow)) { context in
            let distance = size.text + gap
            let offset = overflow
                ? Self.offset(at: context.date.timeIntervalSince(size.start), distance: distance, speed: 2.5 * u)
                : 0
            // Left edge fades only while text is moving past it, so the resting title starts crisp.
            let leftFade = min(1, offset / fade, (distance - offset) / fade)
            HStack(spacing: gap) {
                label
                if overflow { label }
            }
            .offset(x: -offset)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading) // minWidth 0: long text must not widen the card
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { size.box = $0 }
            .mask {
                LinearGradient(stops: overflow ? [
                    .init(color: .black.opacity(1 - leftFade), location: 0),
                    .init(color: .black, location: fade / max(size.box, 1)),
                    .init(color: .black, location: 1 - fade / max(size.box, 1)),
                    .init(color: .clear, location: 1),
                ] : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                startPoint: .leading, endPoint: .trailing)
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
