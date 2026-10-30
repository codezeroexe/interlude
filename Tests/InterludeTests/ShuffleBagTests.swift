import Testing
@testable import Interlude

struct ShuffleBagTests {
    @Test func eachItemOncePerRoundAndNoRepeatAcrossRounds() {
        let pool = ["a", "b", "c", "d", "e"]
        for _ in 0..<50 {
            var queue: [String] = []
            var last: String?
            var picks: [String] = []
            for _ in 0..<15 {
                let pick = ShuffleBag.next(queue: &queue, pool: pool, last: last)!
                picks.append(pick)
                last = pick
            }
            for round in 0..<3 { #expect(Set(picks[round * 5..<round * 5 + 5]) == Set(pool)) }
            for i in 1..<picks.count { #expect(picks[i] != picks[i - 1]) }
        }
    }

    @Test func removedItemsNeverReturn() {
        var queue = ["a", "b", "c"]
        var picks: [String] = []
        var last: String?
        for _ in 0..<12 {
            let pick = ShuffleBag.next(queue: &queue, pool: ["a", "c"], last: last)!
            picks.append(pick)
            last = pick
        }
        #expect(!picks.contains("b"))
    }
}
