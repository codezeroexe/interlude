import Testing
@testable import Interlude

struct LayoutTests {
    private func cell(_ c: Int, _ r: Int) -> Cell { Cell(col: c, row: r) }
    private let standard = WidgetLayout.standard(columns: 5)

    @Test func roundTripsAndRejectsBadValues() {
        #expect(WidgetLayout(rawValue: standard.rawValue) == standard)
        #expect(WidgetLayout(rawValue: "battery@2,0;calendar@3,0;nowPlaying@2,1;clock@2,2") == nil) // old format
        #expect(WidgetLayout(rawValue: "5|battery@0,0;calendar@0,0;nowPlaying@3,1;clock@3,2") == nil) // overlap
        #expect(WidgetLayout(rawValue: "5|battery@0,0;calendar@1,0;nowPlaying@4,1;clock@3,2") == nil) // off the edge
    }

    @Test func movesAnywhereAndSwaps() {
        var layout = standard
        do { let ok = layout.move(.clock, to: cell(1, 2)); #expect(ok) }
        #expect(layout.origin(of: .clock) == cell(1, 2))
        do { let ok = layout.move(.clock, to: cell(4, 2)); #expect(ok) } // last column shifts left
        #expect(layout.origin(of: .clock) == cell(3, 2))
        do { let ok = layout.move(.battery, to: cell(4, 0)); #expect(ok) } // swaps with calendar
        #expect(layout.origin(of: .calendar) == cell(3, 0))
    }
}
