import Foundation
import Testing
@testable import Interlude

struct WorldClockTests {
    @Test func monthEndIsTomorrow() { #expect(WorldClockCard.dayLabel(here: (2026, 11, 30), there: (2026, 12, 1)) == "Tomorrow") }
    @Test func yearEndIsTomorrow() { #expect(WorldClockCard.dayLabel(here: (2026, 12, 31), there: (2027, 1, 1)) == "Tomorrow") }
    @Test func monthStartIsYesterday() { #expect(WorldClockCard.dayLabel(here: (2026, 12, 1), there: (2026, 11, 30)) == "Yesterday") }
    @Test func sameDayIsToday() { #expect(WorldClockCard.dayLabel(here: (2026, 5, 4), there: (2026, 5, 4)) == "Today") }
    @Test func offsetLinesSplitsDayAndAmount() {
        let utc = TimeZone(identifier: "UTC")!, d = Date(timeIntervalSince1970: 0)
        let p = WorldClockCard.offsetParts(utc, at: d)
        #expect(WorldClockCard.offsetLines(utc, at: d) == "\(p.day)\n\(p.amount)")
        #expect(WorldClockCard.offset(utc, at: d) == "\(p.day), \(p.amount)")
    }
}
