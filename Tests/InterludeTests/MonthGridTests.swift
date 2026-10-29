import Foundation
import Testing
@testable import Interlude

struct MonthGridTests {
    private func date(_ y: Int, _ m: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: y, month: m, day: 15))!
    }

    private func check(_ y: Int, _ m: Int, blanks: Int, days: Int) {
        let grid = MonthGrid.days(for: date(y, m), calendar: Calendar(identifier: .gregorian))
        #expect(grid.prefix { $0 == nil }.count == blanks)
        #expect(grid.compactMap { $0 }.count == days)
    }

    @Test func october2026StartsThursday() { check(2026, 10, blanks: 3, days: 31) }
    @Test func february2027StartsMonday() { check(2027, 2, blanks: 0, days: 28) }
    @Test func november2026StartsSunday() { check(2026, 11, blanks: 6, days: 30) }
}
