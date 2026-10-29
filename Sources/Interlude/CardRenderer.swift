import AppKit
import SwiftUI

/// Debug aid: draws every card at this screen's size into PNGs. Glass doesn't render off screen,
/// so cards sit on a plain dark backdrop.
@MainActor
enum CardRenderer {
    /// Draws each Settings pane into a PNG, in a window off screen. Glass draws as a plain fill.
    static func renderSettings(overlay: OverlayController, to folder: URL, done: @escaping () -> Void) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NowPlaying.screenshots = true
        // Wallpaper stills to rotate through, one per picture: `<folder>/backdrops/*.jpg`, if there.
        let backdrops = ((try? FileManager.default.contentsOfDirectory(at: folder.appending(path: "backdrops"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "jpg" }.sorted { $0.path < $1.path }
        func backdrop(_ i: Int) {
            if !backdrops.isEmpty { PreviewBackdrop.image = NSImage(contentsOf: backdrops[i % backdrops.count]) }
        }
        for (i, url) in backdrops.enumerated() {
            backdrop(i)
            renderStandby(overlay: overlay, to: folder, name: "-" + url.deletingPathExtension().lastPathComponent)
        }
        backdrop(0)
        renderStandby(overlay: overlay, to: folder)
        let panes = SettingsPane.allCases
        func next(_ i: Int) {
            guard i < panes.count else { return onboarding(0) }
            backdrop(i)
            UserDefaults.standard.set(panes[i].rawValue, forKey: "settingsPane")
            let view = NSHostingView(rootView: SettingsView(overlay: overlay).environment(\.plainCards, true).background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 860, height: 1500), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("\(panes[i].rawValue).png"))
                }
                window.orderOut(nil)
                next(i + 1)
            }
        }
        // Then each step of the welcome window.
        func onboarding(_ step: Int) {
            guard step <= 4 else { return done() }
            backdrop(step + 3)
            let view = NSHostingView(rootView: OnboardingView(overlay: overlay, step: step).environment(\.plainCards, true).background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: -3000, y: 0, width: 720, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = view
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("welcome-\(step + 1).png"))
                }
                window.orderOut(nil)
                onboarding(step + 1)
            }
        }
        next(0)
    }

    /// The standby screen with sample data, and the welcome window's picture, for the README.
    static func renderStandby(overlay: OverlayController, to folder: URL, name suffix: String = "") {
        let entrance = Entrance()
        entrance.shown = true
        let model = overlay.demo
        let size = CGSize(width: 1600, height: 1000)
        let screen = ZStack {
            PreviewBackdrop()
            WidgetCanvas(model: model, nowPlaying: model.nowPlaying, night: false, grid: Grid(size: size, rows: GridSize.rows), dismiss: {})
        }
        .frame(width: size.width, height: size.height)
        .frostBackdrop(size)
        .clipped()
        let scene = StandbyScene(model: model)
            .environment(\.clockFontOverride, .instrumentSerif)
            .frame(width: 1100, height: 400)
        for (name, view) in [("standby", AnyView(screen)), ("scene", AnyView(scene))] {
            let renderer = ImageRenderer(content: view
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .environment(\.plainCards, true)
                .environmentObject(entrance))
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: folder.appendingPathComponent("\(name)\(suffix).png"))
        }
        guard suffix.isEmpty else { return }
        // Each card alone, on a clear background, at the standby screen's size.
        let grid = Grid(size: size, rows: GridSize.rows)
        let cards: [(Widget, WidgetSize, Int)] = [(.clock, .large, 0), (.clock, .medium, 0), (.nowPlaying, .medium, 0), (.calendar, .small, 0),
                                                  (.battery, .small, 0), (.weather, .medium, 0), (.reminders, .medium, 0), (.worldClock, .medium, 0)]
        for (widget, cardSize, style) in cards {
            let renderer = ImageRenderer(content: WidgetCardView(model: model, widget: widget, size: cardSize, style: style, grid: grid)
                .environment(\.clockFontOverride, .instrumentSerif)
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .environment(\.plainCards, true)
                .environmentObject(entrance))
            renderer.scale = 2
            guard let tiff = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: folder.appendingPathComponent("card-\(widget.rawValue)-\(cardSize.rawValue).png"))
        }
        print("card radius \(grid.radius)")
    }

    static func render(model: OverlayModel, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let grid = Grid(size: NSScreen.main?.frame.size ?? CGSize(width: 1710, height: 1112))
        let entrance = Entrance()
        entrance.shown = true
        if model.nowPlaying.track == nil {
            model.nowPlaying.preview(NowPlaying.sample.track!, artwork: NowPlaying.sample.artwork)
        }
        model.battery.preview()
        model.calendar.preview()
        model.weather.preview()
        model.reminders.preview()
        let savedFont = UserDefaults.standard.string(forKey: ClockFont.key)
        defer { UserDefaults.standard.set(savedFont, forKey: ClockFont.key) }
        for font in ClockFont.allCases {
        UserDefaults.standard.set(font.rawValue, forKey: ClockFont.key)
        for widget in Widget.allCases where font == .sfPro || widget == .clock {
          for size in widget.sizes {
           for style in widget.styles(size).indices {
            let card = WidgetCardView(model: model, widget: widget, size: size, style: style, grid: grid)
            let view = card
                .padding(20)
                .background {
                    // A blue, wallpaper-like backdrop with text, to judge see-through effects.
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.1, green: 0.2, blue: 0.45), Color(red: 0.35, green: 0.5, blue: 0.7)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        Text("Behind the card").font(.system(size: 60, weight: .bold)).foregroundStyle(.yellow.opacity(0.8))
                    }
                }
                .foregroundStyle(.white)
                .environment(\.colorScheme, .dark)
                .environment(\.plainCards, true)
                .environmentObject(entrance)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                  let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { continue }
            let suffix = font == .sfPro ? "" : "-serif"
            try? png.write(to: folder.appendingPathComponent("\(widget.rawValue)-\(size.rawValue)\(style + 1)\(suffix).png"))
           }
          }
        }
        }
    }
}
