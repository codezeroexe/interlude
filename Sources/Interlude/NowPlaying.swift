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
}

@MainActor
final class NowPlaying: ObservableObject {
    @Published private(set) var track: Track?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var palette = Palette.fallback
    private var pausedSince: Date?
    private var emptyReads = 0
    private var timer: Timer?
    private let bridge = PlayerBridge()

    /// The card shows while playing and for 5 minutes after pausing.
    var visible: Bool {
        guard let track else { return false }
        return track.playing || Date().timeIntervalSince(pausedSince ?? .now) < 5 * 60
    }

    /// Polls once a second while the overlay is showing.
    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

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
