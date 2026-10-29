import Foundation
import Testing
@testable import Interlude

struct MarqueeTests {
    // 100 pt to travel at 50 pt/s with a 2.5 s hold: 4.5 s cycle.
    private func offset(_ t: Double) -> CGFloat {
        Marquee.offset(at: t, distance: 100, speed: 50)
    }

    @Test func holdsThenScrollsThenLoops() {
        #expect(offset(1) == 0)          // holding
        #expect(offset(3.5) == 50)       // halfway
        #expect(offset(4.49) > 99)       // second copy almost home
        #expect(offset(4.5) == 0)        // seamless restart
        #expect(offset(6) == 0)          // holding again
    }
}
