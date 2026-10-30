import AVFoundation
import SwiftUI

/// Reads the catalog of Apple's aerial screensaver videos that ships with macOS.
enum AerialCatalog {
    static let root = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer")

    struct Category: Identifiable {
        let id: String   // e.g. "AerialCategorySpace"
        let name: String // e.g. "Space"
        let aerials: [Aerial]
    }

    struct Aerial: Identifiable {
        let id: String
        let name: String
        let url: URL
        /// A still from Apple's servers, for the picker in Settings.
        let preview: URL?
    }

    /// Wallpaper setting: "aerials:<id>,<id>,...". Older versions stored "all", "category:<key>" or "aerial:<id>".
    static let selectionKey = "wallpaper"
    static let defaultSelection = "category:AerialCategorySpace"

    /// The wallpaper catalog (System Settings › Wallpaper, 164 aerials, keeps your downloads in videos/)
    /// and the older screensaver catalog as a fallback.
    private static let sources: [(manifest: URL, strings: URL, localFile: (String) -> URL?)] = {
        let wallpaper = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.apple.wallpaper/aerials")
        let stringsPath = "TVIdleScreenStrings.bundle/Contents/Resources/Localizable.nocache.loctable"
        return [
            (wallpaper.appending(path: "manifest/entries.json"), wallpaper.appending(path: "manifest/" + stringsPath), { id in
                let url = wallpaper.appending(path: "videos/\(id).mov")
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }),
            (root.appending(path: "entries.json"), root.appending(path: stringsPath), localFile),
        ]
    }()

    /// Every aerial on this Mac, by category, named as System Settings names them ("North Atlantic").
    /// Plays downloaded files when present, otherwise streams from Apple's servers.
    static let categories: [Category] = {
        for source in sources {
            guard let data = try? Data(contentsOf: source.manifest),
                  let catalog = try? JSONDecoder().decode(Catalog.self, from: data)
            else { continue }
            let names = displayNames(at: source.strings)
            return catalog.categories.map { category in
                let categoryName = names[category.localizedNameKey] ?? category.localizedNameKey.replacingOccurrences(of: "AerialCategory", with: "")
                var unnamed = 0              // fallback counter
                var base: String?            // nearest preceding named aerial, trimmed
                var seen: [String: Int] = [:]
                return Category(
                    id: category.localizedNameKey,
                    name: categoryName,
                    aerials: catalog.assets.filter { $0.categories.contains(category.id) }.compactMap { asset in
                        guard let url = source.localFile(asset.id) ?? asset.url4K.flatMap(URL.init(string:)) else { return nil }
                        var name = asset.localizedNameKey.flatMap { names[$0] } ?? asset.accessibilityLabel ?? "Aerial"
                        // Apple's table lacks some names, leaving a raw key like "GG_A_DAY_BLUFFS_C35".
                        // Underscore only: scripts without case (CJK, Arabic) have no lowercase letters either.
                        if name.contains("_") {
                            if let base {
                                seen[base, default: 1] += 1
                                name = "\(base) \(seen[base]!)"
                            } else {
                                unnamed += 1
                                name = "\(categoryName) \(unnamed)"
                            }
                        } else {
                            // "Golden Gate Sunset" -> "Golden Gate"; shorter names stay whole.
                            let words = name.split(separator: " ")
                            base = words.count >= 3 ? words.dropLast().joined(separator: " ") : name
                        }
                        return Aerial(id: asset.id, name: name, url: url, preview: asset.previewImage.flatMap(URL.init(string:)))
                    }
                )
            }.filter { !$0.aerials.isEmpty }
        }
        return []
    }()

    /// Apple's localized names for categories and aerials, in your preferred language (English fallback).
    private static func displayNames(at url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String: String]]
        else { return [:] }
        let language = Locale.preferredLanguages.lazy
            .compactMap { pref in table.keys.first { pref.hasPrefix($0) } }.first ?? "en"
        return table[language] ?? table["en"] ?? [:]
    }

    /// The aerial ids a setting stands for, old formats included. Everything if it matches nothing.
    static func selectedIDs(from selection: String) -> Set<String> {
        let all = Set(categories.flatMap(\.aerials).map(\.id))
        let parts = selection.split(separator: ":", maxSplits: 1).map(String.init)
        let picked: Set<String> = switch (parts.first, parts.last) {
        case ("aerials", let ids?) where parts.count == 2: Set(ids.split(separator: ",").map(String.init))
        case ("category", let key?): Set(categories.first { $0.id == key }?.aerials.map(\.id) ?? [])
        case ("aerial", let id?): [id]
        default: all
        }
        let valid = picked.intersection(all)
        return valid.isEmpty ? all : valid
    }

    static func selection(of ids: Set<String>) -> String { "aerials:" + ids.sorted().joined(separator: ",") }

    private static let urls: [String: URL] = Dictionary(
        categories.flatMap(\.aerials).map { ($0.id, $0.url) }, uniquingKeysWith: { first, _ in first })

    /// Where an aerial plays from now (file once downloaded, otherwise Apple's stream).
    static func url(of id: String) -> URL? { urls[id] }

    private static func localFile(for id: String) -> URL? {
        for folder in ["4KSDR240FPS", "4KSDR", "4KHDR", "2KSDR", "2KHDR", "2KAVC"] {
            let url = root.appending(path: "\(folder)/\(id).mov")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    private struct Catalog: Decodable {
        let assets: [Asset]
        let categories: [CategoryEntry]
    }

    private struct Asset: Decodable {
        let id: String
        let categories: [String]
        let accessibilityLabel: String?
        let localizedNameKey: String?
        let url4K: String?
        let previewImage: String?
        enum CodingKeys: String, CodingKey {
            case id, categories, accessibilityLabel, localizedNameKey, previewImage
            case url4K = "url-4K-SDR-240FPS"
        }
    }

    private struct CategoryEntry: Decodable {
        let id: String
        let localizedNameKey: String
    }
}

/// Shuffle without repeats: plays every item once per round, never the same one twice in a row.
enum ShuffleBag {
    static func next(queue: inout [String], pool: [String], last: String?) -> String? {
        let allowed = Set(pool)
        queue.removeAll { !allowed.contains($0) }
        if queue.isEmpty {
            queue = pool.shuffled()
            if queue.count > 1, queue.first == last, let j = queue.indices.dropFirst().randomElement() { queue.swapAt(0, j) }
        }
        return queue.isEmpty ? nil : queue.removeFirst()
    }
}

/// Plays shuffled aerials from the chosen wallpaper setting, muted. Two players take turns: the next video
/// waits paused on the hidden one, then crossfades in over the last seconds of the current one,
/// so there is never a hard cut (also when the setting is a single looping aerial).
@MainActor
final class AerialPlayer {
    private let players = [AVPlayer(), AVPlayer()]
    let layers: [AVPlayerLayer]
    private var front = 0
    private var back: Int { 1 - front }
    private var crossfading = false
    private var pool: [String] = []
    /// Aerial id loaded in each player, so unload() can put the unseen one back.
    private var loaded: [Int: String] = [:]
    private var selection = ""
    private var observers: [Any] = []
    private var statusWatch: [NSKeyValueObservation?] = [nil, nil]
    private var wantsPlay = false
    private static let fade = 1.5
    private static let queueKey = "wallpaperQueue"
    private static let lastKey = "wallpaperLast"

    init() {
        layers = players.map { player in
            player.isMuted = true
            player.allowsExternalPlayback = false
            player.preventsDisplaySleepDuringVideoPlayback = false
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            return layer
        }
        layers[1].opacity = 0
        observers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let item = (note.object as AnyObject?).map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.ended(item) }
        })
        for (i, player) in players.enumerated() {
            observers.append(player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
                MainActor.assumeIsolated { self?.tick(player: i, at: time) }
            })
        }
    }

    /// Picks up a changed wallpaper setting each time the overlay opens.
    func play() {
        let current = UserDefaults.standard.string(forKey: AerialCatalog.selectionKey) ?? AerialCatalog.defaultSelection
        if current != selection {
            // Only a change after start clears the saved order; the first read keeps it across restarts.
            if !selection.isEmpty { UserDefaults.standard.removeObject(forKey: Self.queueKey) }
            selection = current
            pool = Array(AerialCatalog.selectedIDs(from: current))
            restart()
        } else if players[front].currentItem == nil {
            restart()
        }
        wantsPlay = true
        players[front].play()
        if crossfading { players[back].play() } // the outgoing video finishes its fade
    }

    func pause() {
        wantsPlay = false
        players.forEach { $0.pause() }
    }

    /// Releases both 4K items so nothing keeps buffering while the overlay is closed; play() reloads.
    func unload() {
        pause()
        // The preloaded next video was drawn but never shown: put it back so the round stays complete.
        if !crossfading, let id = loaded[back] {
            var queue = UserDefaults.standard.stringArray(forKey: Self.queueKey) ?? []
            queue.insert(id, at: 0)
            UserDefaults.standard.set(queue, forKey: Self.queueKey)
        }
        crossfading = false
        loaded = [:]
        players.forEach { $0.replaceCurrentItem(with: nil) }
        statusWatch = [nil, nil]
    }

    /// Hard switch for the first open or a new setting; the overlay's own fade covers it.
    private func restart() {
        crossfading = false
        load(into: front)
        load(into: back)
        layers.forEach { $0.removeAllAnimations() }
        layers[front].opacity = 1
        layers[back].opacity = 0
    }

    /// Next video from the saved shuffle order; the order survives restarts.
    private func nextVideo() -> (id: String, url: URL)? {
        let defaults = UserDefaults.standard
        var queue = defaults.stringArray(forKey: Self.queueKey) ?? []
        let id = ShuffleBag.next(queue: &queue, pool: pool, last: defaults.string(forKey: Self.lastKey))
        defaults.set(queue, forKey: Self.queueKey)
        defaults.set(id, forKey: Self.lastKey)
        return id.flatMap { id in AerialCatalog.url(of: id).map { (id, $0) } }
    }

    /// Queues the next video, paused at its start, so it is ready when its turn comes.
    private func load(into i: Int) {
        guard let next = nextVideo() else { return }
        loaded[i] = next.id
        let item = AVPlayerItem(url: next.url)
        let id = ObjectIdentifier(item)
        statusWatch[i] = item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.failed(i, id) } }
        }
        players[i].replaceCurrentItem(with: item)
    }

    /// An offline or broken stream: try another video a few seconds later instead of a black screen forever.
    private func failed(_ i: Int, _ id: ObjectIdentifier) {
        guard let item = players[i].currentItem, ObjectIdentifier(item) == id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let now = self.players[i].currentItem, ObjectIdentifier(now) == id else { return }
                self.load(into: i)
                if i == self.front, self.wantsPlay { self.players[i].play() }
            }
        }
    }

    private func tick(player i: Int, at time: CMTime) {
        guard i == front, !crossfading, let item = players[i].currentItem, item.duration.isNumeric,
              time.seconds >= item.duration.seconds - Self.fade else { return }
        crossfade()
    }

    /// Fallback for a video whose length was never known, so the crossfade did not start early.
    private func ended(_ item: ObjectIdentifier?) {
        guard !crossfading, let current = players[front].currentItem, item == ObjectIdentifier(current) else { return }
        crossfade()
    }

    private func crossfade() {
        guard players[back].currentItem != nil else { return }
        crossfading = true
        let old = front
        front = back
        players[front].play()
        animate(layers[front], to: 1)
        animate(layers[old], to: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fade) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.crossfading else { return }
                self.crossfading = false
                self.players[old].pause()
                self.load(into: old)
            }
        }
    }

    private func animate(_ layer: CALayer, to opacity: Float) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = opacity
        animation.duration = Self.fade
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.opacity = opacity
        layer.add(animation, forKey: "fade")
    }
}

struct AerialView: NSViewRepresentable {
    let player: AerialPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let root = CALayer()
        view.layer = root
        view.wantsLayer = true
        for layer in player.layers {
            layer.frame = root.bounds
            root.addSublayer(layer)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
