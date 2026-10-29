import AppKit
import SwiftUI

/// Debug aid: draws every card at this screen's size into PNGs. Glass doesn't render off screen,
/// so cards sit on a plain dark backdrop.
@MainActor
enum CardRenderer {
    static func render(model: OverlayModel, to folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let grid = Grid(size: NSScreen.main?.frame.size ?? CGSize(width: 1710, height: 1112))
        let entrance = Entrance()
        entrance.shown = true
        for widget in Widget.allCases {
            let card = Group {
                switch widget {
                case .battery: BatteryCard(battery: model.battery, grid: grid)
                case .calendar: CalendarCard(grid: grid)
                case .nowPlaying: NowPlayingCard(nowPlaying: model.nowPlaying, grid: grid)
                case .clock: ClockCard(weather: model.weather, grid: grid)
                case .weather: WeatherCard(weather: model.weather, grid: grid)
                case .reminders: RemindersCard(reminders: model.reminders, grid: grid)
                case .worldClock: WorldClockCard(grid: grid)
                case .timer: TimerCard(timer: model.timer, grid: grid)
                }
            }
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
            try? png.write(to: folder.appendingPathComponent("\(widget.rawValue).png"))
        }
    }
}
