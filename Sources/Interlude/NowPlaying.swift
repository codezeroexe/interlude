import AppKit
import CoreServices

/// The track playing in Music or Spotify, read with AppleScript.
struct Track {
    enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"
    }

    let player: Player
    let title: String
    let artist: String
    let duration: Double
    let position: Double
    let playing: Bool
    let artworkURL: URL?
    var sampledAt = Date.now

    var id: String { "\(player.rawValue)|\(title)|\(artist)" }

    /// What the Now Playing card shows when nothing plays.
    static let idle = Track(player: .music, title: "Not Playing", artist: "Apple Music", duration: 0,
                            position: 0, playing: false, artworkURL: nil)
}

@MainActor
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette = Palette.fallback

    /// Debug: shows a made-up track, for the card renderer when nothing is playing.
    func preview(_ track: Track, artwork: NSImage?) {
        self.track = track
        self.artwork = artwork
    }
    /// Debug: README screenshots show the empty card, never a song or the one playing now.
    static var screenshots = false

    /// A made-up track for previews in Settings while nothing plays. Never polls.
    static var sample: NowPlaying { screenshots ? empty : filled }
    private static let empty = NowPlaying()
    private static let filled: NowPlaying = {
        let sample = NowPlaying()
        // Rings like a speaker cone, so the cover styles have something to show.
        let art = NSImage(size: NSSize(width: 600, height: 600), flipped: false) { rect in
            for (i, white) in [0.4, 0.1, 0.5, 0.08, 0.6, 0.12, 0.85].enumerated() {
                NSColor(white: white, alpha: 1).setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: CGFloat(i) * 42, dy: CGFloat(i) * 42)).fill()
            }
            return true
        }
        sample.preview(Track(player: .music, title: "Lulu", artist: "The Neighbourhood", duration: 200,
                             position: 20, playing: true, artworkURL: nil), artwork: art)
        return sample
    }()

    private var pausedSince: Date?
    private var emptyReads = 0
    private var timer: Timer?
    private let bridge = PlayerBridge()

    /// The card shows while playing and for 5 minutes after pausing.
    var visible: Bool {
        guard let track else { return false }
        return track.playing || Date().timeIntervalSince(pausedSince ?? .now) < 5 * 60
    }

    /// Polls once a second while the overlay or Settings is showing. Each `start` needs its own `stop`.
    func start() {
        users += 1
        guard timer == nil, !Self.screenshots else { return }
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        users = max(0, users - 1)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
    }

    private var users = 0

    /// Asks for permission to control running players. Called while the overlay is hidden,
    /// so the system prompt isn't stuck behind it.
    func requestPermissions() {
        let running = Self.runningPlayers()
        bridge.queue.async { [bridge] in running.forEach { _ = bridge.permitted($0, ask: true) } }
    }

    /// Playback position now, counting forward from the last poll while playing.
    enum Command: String {
        case playPause = "playpause", next = "next track", previous = "previous track"
    }

    func send(_ command: Command) {
        guard let player = track?.player else { return }
        bridge.queue.async { [bridge] in
            bridge.run("tell application id \"\(player.rawValue)\" to \(command.rawValue)")
            DispatchQueue.main.async { self.poll() }
        }
    }

    private func poll() {
        let running = Self.runningPlayers()
        bridge.queue.async { [bridge] in
            let track = bridge.read(running)
            DispatchQueue.main.async { self.apply(track) }
        }
    }

    private func apply(_ new: Track?) {
        // While skipping, the player can report nothing for a moment. Ignore up to two empty reads
        // so the card doesn't flicker away and back.
        if new == nil, track != nil, emptyReads < 2 {
            emptyReads += 1
            return
        }
        emptyReads = 0
        let wasVisible = visible
        let changedTrack = new?.id != track?.id
        if changedTrack { loadArtwork(for: new) }
        if new?.playing != false {
            pausedSince = nil
        } else if pausedSince == nil {
            // ponytail: counts from when the overlay first saw it paused, not from the real pause.
            pausedSince = .now
        }
        let nowVisible = new.map { $0.playing || Date().timeIntervalSince(pausedSince ?? .now) < 5 * 60 } ?? false
        // Animate only when the layout changes (card appears/leaves, new song), not on every position tick.
        if changedTrack || nowVisible != wasVisible {
            Motion.animate { track = new }
        } else {
            track = new
        }
    }

    /// Keeps showing the previous cover until the new one has loaded, then crossfades, so skipping
    /// never flashes the empty placeholder.
    private func loadArtwork(for track: Track?) {
        guard let track else { artwork = nil; return }
        bridge.queue.async { [bridge] in
            var data: Data?
            if let url = track.artworkURL {
                data = try? Data(contentsOf: url)
            } else if track.player == .music {
                data = bridge.run("tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track")?.data
            }
            let image = data.flatMap(NSImage.init(data:))
            let palette = image.flatMap(Palette.init(image:)) ?? .fallback
            DispatchQueue.main.async {
                if self.track?.id == track.id { Motion.animate(Motion.fade) { self.artwork = image; self.palette = palette } }
            }
        }
    }

    private static func runningPlayers() -> [Track.Player] {
        let ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        return Track.Player.allCases.filter { ids.contains($0.rawValue) }
    }
}

/// All AppleScript work happens on one serial queue so a slow player never blocks the UI.
final class PlayerBridge {
    let queue = DispatchQueue(label: "Interlude.players")
    private var scripts: [String: NSAppleScript] = [:]

    /// The playing track, else a paused one. Never launches a player or prompts.
    func read(_ running: [Track.Player]) -> Track? {
        let tracks = running.filter { permitted($0, ask: false) }.compactMap(track)
        return tracks.first(where: \.playing) ?? tracks.first
    }

    private func track(from player: Track.Player) -> Track? {
        let artwork = player == .spotify ? ", artwork url of t" : ""
        let source = """
        tell application id "\(player.rawValue)"
            if player state is stopped then return {}
            set t to current track
            return {name of t, artist of t, duration of t, player position, player state is playing\(artwork)}
        end tell
        """
        guard let list = run(source), list.numberOfItems >= 5 else { return nil }
        let duration = list.atIndex(3)?.doubleValue ?? 0
        return Track(
            player: player,
            title: list.atIndex(1)?.stringValue ?? "",
            artist: list.atIndex(2)?.stringValue ?? "",
            duration: player == .spotify ? duration / 1000 : duration, // Spotify reports milliseconds
            position: list.atIndex(4)?.doubleValue ?? 0,
            playing: list.atIndex(5)?.booleanValue ?? false,
            artworkURL: list.numberOfItems >= 6 ? list.atIndex(6)?.stringValue.flatMap(URL.init(string:)) : nil
        )
    }

    @discardableResult
    func run(_ source: String) -> NSAppleEventDescriptor? {
        let script = scripts[source] ?? NSAppleScript(source: source)
        scripts[source] = script
        var error: NSDictionary?
        let result = script?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }

    /// Automation permission for a player. With `ask`, shows the system prompt if needed.
    func permitted(_ player: Track.Player, ask: Bool) -> Bool {
        let target = NSAppleEventDescriptor(bundleIdentifier: player.rawValue)
        return withExtendedLifetime(target) {
            AEDeterminePermissionToAutomateTarget(target.aeDesc, AEEventClass(typeWildCard), AEEventID(typeWildCard), ask) == noErr
        }
    }
}
