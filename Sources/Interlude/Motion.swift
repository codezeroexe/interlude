import AppKit
import SwiftUI

/// One motion system for the whole overlay. Every change that moves, adds or removes something on screen
/// goes through `Motion.animate`, so layout shifts (pills arriving, the now
/// playing card appearing) all move with the same spring instead of jumping.
enum Motion {
    private static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Layout: things moving, resizing, appearing.
    static var layout: Animation { reduced ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.12) }
    /// Content swaps in place: artwork, text, colours.
    static var fade: Animation { .easeInOut(duration: reduced ? 0.2 : 0.45) }

    static func animate(_ animation: Animation = layout, _ change: () -> Void) {
        withAnimation(animation, change)
    }

    /// Small items such as pills pop in and out.
    static var pop: AnyTransition {
        reduced ? .opacity : .opacity.combined(with: .scale(scale: 0.85))
    }
}
