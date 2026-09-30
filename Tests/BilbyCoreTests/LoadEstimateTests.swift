import Testing

@testable import BilbyCore

@Suite("Load estimate")
struct LoadEstimateTests {
    @Test("with no load to go on, it gives no number")
    func noHistory() {
        #expect(LoadEstimate().fraction(after: .seconds(5)) == nil)
    }

    @Test("halfway through the last load's time reads half")
    func halfway() {
        #expect(LoadEstimate(expected: .seconds(20)).fraction(after: .seconds(10)) == 0.5)
    }

    @Test("it moves in steps of five percent")
    func steps() {
        // 43% of the way shows as 40%: an estimate is not precise to the
        // percent, and every change redraws the menu if it is open.
        #expect(LoadEstimate(expected: .seconds(100)).fraction(after: .seconds(43)) == 0.40)
    }

    @Test("it never claims to be done before it is")
    func ceiling() {
        #expect(LoadEstimate(expected: .seconds(20)).fraction(after: .seconds(40)) == 0.95)
    }

    @Test("a finished load teaches the next estimate")
    func learns() {
        var estimate = LoadEstimate()
        estimate.learn(.seconds(16))
        #expect(estimate.fraction(after: .seconds(8)) == 0.5)
    }
}
