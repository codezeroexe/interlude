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

    /// Wallpaper setting: "all", "category:<key>" or "aerial:<id>".
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
                Category(
                    id: category.localizedNameKey,
                    name: names[category.localizedNameKey] ?? category.localizedNameKey.replacingOccurrences(of: "AerialCategory", with: ""),
                    aerials: catalog.assets.filter { $0.categories.contains(category.id) }.compactMap { asset in
                        guard let url = source.localFile(asset.id) ?? asset.url4K.flatMap(URL.init(string:)) else { return nil }
                        let name = asset.localizedNameKey.flatMap { names[$0] } ?? asset.accessibilityLabel ?? "Aerial"
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

    /// Videos for a wallpaper setting; falls back to everything if the setting matches nothing.
    static func videos(for selection: String) -> [URL] {
        let all = categories.flatMap(\.aerials)
        let parts = selection.split(separator: ":", maxSplits: 1).map(String.init)
        let picked: [Aerial] = switch (parts.first, parts.last) {
        case ("category", let key?): categories.first { $0.id == key }?.aerials ?? []
        case ("aerial", let id?): all.filter { $0.id == id }
        default: all
        }
        return (picked.isEmpty ? all : picked).map(\.url)
    }

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

/// Plays a random aerial from the chosen wallpaper setting, muted, and moves to another when one ends.
@MainActor
final class AerialPlayer {
    let player = AVPlayer()
    private var videos: [URL] = []
    private var selection = ""
    private var endObserver: NSObjectProtocol?

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.next() }
        }
    }

    /// Picks up a changed wallpaper setting each time the overlay opens.
    func play() {
        let current = UserDefaults.standard.string(forKey: AerialCatalog.selectionKey) ?? AerialCatalog.defaultSelection
        if current != selection {
            selection = current
            videos = AerialCatalog.videos(for: current)
            next()
        } else if player.currentItem == nil {
            next()
        }
        player.play()
    }

    func pause() {
        player.pause()
    }

    private func next() {
        guard let url = videos.randomElement() else { return }
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
    }
}

struct AerialView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
