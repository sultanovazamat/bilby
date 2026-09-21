import Testing

@testable import BilbyCore

@Suite("Pause scale")
struct PauseScaleTests {
    /// A speaker with `within` between words and `between` between sentences.
    private func speaker(within: Double, between: Double, sentences: Int, words: Int) -> PauseScale {
        var scale = PauseScale()
        for _ in 0..<sentences {
            for _ in 0..<words { scale.saw(gap: within) }
            scale.saw(gap: between)
        }
        return scale
    }

    @Test("before it has heard enough it uses a plain default")
    func defaultsUntilItKnows() {
        var scale = PauseScale()
        #expect(scale.boundary == PauseScale.untilKnown)
        scale.saw(gap: 0.1)
        #expect(scale.boundary == PauseScale.untilKnown)
    }

    @Test("a measured speaker lands between their words and their sentences")
    func landsBetween() {
        let scale = speaker(within: 0.12, between: 0.70, sentences: 12, words: 11)
        #expect(scale.boundary > 0.12)
        #expect(scale.boundary <= 0.70)
    }

    @Test("a fast speaker gets a lower bar than a slow one")
    func adaptsToPace() {
        let fast = speaker(within: 0.04, between: 0.34, sentences: 12, words: 11)
        let slow = speaker(within: 0.25, between: 1.10, sentences: 12, words: 11)
        #expect(fast.boundary < slow.boundary)
        #expect(fast.boundary <= 0.34)
        #expect(slow.boundary > 0.34)
    }

    @Test("nothing absurd gets through, however strange the speech")
    func clamped() {
        var racing = PauseScale()
        for _ in 0..<200 { racing.saw(gap: 0.001) }
        #expect(racing.boundary >= PauseScale.shortest)

        var halting = PauseScale()
        for _ in 0..<200 { halting.saw(gap: 9.0) }
        #expect(halting.boundary <= PauseScale.longest)
    }

    @Test("it follows the speech it is hearing now, not the speech it heard before")
    func forgetsOldSpeech() {
        var scale = speaker(within: 0.25, between: 1.10, sentences: 12, words: 11)
        let slow = scale.boundary
        for _ in 0..<PauseScale.remembered { scale.saw(gap: 0.04) }
        #expect(scale.boundary < slow)
    }
}
