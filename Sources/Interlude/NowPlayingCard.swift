import SwiftUI

/// Medium (2:1) card: artwork, title, artist, progress and Mac-style controls.
struct NowPlayingCard: View {
    @ObservedObject var nowPlaying: NowPlaying
    @StateObject private var hover = HoverState()
    let grid: Grid

    var body: some View {
        if let track = nowPlaying.track {
            let art = grid.s - 3.6 * grid.u
            HStack(spacing: 2 * grid.u) {
                artwork
                    .frame(width: art, height: art)
                    .clipShape(RoundedRectangle(cornerRadius: 1.8 * grid.u, style: .continuous))
                    .id(nowPlaying.artwork.map(ObjectIdentifier.init)) // crossfade when the cover itself changes
                    .transition(.opacity)

                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("NOW PLAYING")
                        .font(.system(size: 1.35 * grid.u, weight: .semibold))
                        .tracking(0.08 * grid.u)
                        .opacity(0.55)
                    Marquee(text: track.title, u: grid.u)
                        .font(.system(size: 2.4 * grid.u, weight: .semibold))
                        .padding(.top, 0.3 * grid.u)
                    Marquee(text: track.artist, u: grid.u)
                        .font(.system(size: 2.1 * grid.u))
                        .opacity(0.8)
                    progress(track)
                        .padding(.top, 1 * grid.u)
                    if hover.on {
                        HStack {
                            Text(Self.time(track.position))
                            Spacer()
                            Text("-" + Self.time(track.duration - track.position))
                        }
                        .font(.system(size: 1.25 * grid.u))
                        .monospacedDigit()
                        .opacity(0.6)
                        .padding(.top, 0.4 * grid.u)
                        .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) { controls(track) }
            }
            .animation(.easeInOut(duration: 0.6), value: track.id)
            .padding(1.8 * grid.u)
            .frame(width: grid.wide, height: grid.s)
            .glass(grid)
            .onHover { on in withAnimation(.easeOut(duration: 0.25)) { hover.on = on } }
        }
    }

    /// When on, the cover is printed into the glass: it keeps only its light and dark, takes its colour
    /// from the wallpaper behind (luminosity blend), and lets that show through, like the other cards.
    @AppStorage("monochromeArtwork") private var monochrome = true

    @ViewBuilder private var artwork: some View {
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

    private func progress(_ track: Track) -> some View {
        let fraction = track.duration > 0 ? min(1, track.position / track.duration) : 0
        return Capsule().fill(.white.opacity(0.25))
            .frame(height: 0.4 * grid.u)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule().fill(.white).frame(width: geo.size.width * fraction)
                }
            }
            .animation(.linear(duration: 1), value: fraction)
    }

    private func controls(_ track: Track) -> some View {
        HStack(spacing: 1.2 * grid.u) {
            control("backward.fill", .previous)
            control(track.playing ? "pause.fill" : "play.fill", .playPause)
            control("forward.fill", .next)
        }
        .font(.system(size: 2.2 * grid.u))
    }

    private func control(_ symbol: String, _ command: NowPlaying.Command) -> some View {
        Button { nowPlaying.send(command) } label: {
            Image(systemName: symbol).contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
    }

    private static func time(_ seconds: Double) -> String {
        Duration.seconds(max(0, seconds)).formatted(.time(pattern: .minuteSecond))
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
