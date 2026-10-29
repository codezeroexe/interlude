import AppKit

/// The menu bar icon: a sun resting on two horizon lines (option 1 in reference/menubar-icons.html).
/// A template image, so macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 13, width: 16, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(roundedRect: NSRect(x: 3.5, y: 10, width: 11, height: 1.6), xRadius: 0.8, yRadius: 0.8).fill()
            // The sun's top half, sitting on the shorter line.
            let sun = NSBezierPath()
            sun.appendArc(withCenter: NSPoint(x: 9, y: 8.4), radius: 3.4, startAngle: 180, endAngle: 0, clockwise: false)
            sun.close()
            sun.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Interlude"
        return image
    }()
}
