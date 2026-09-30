import Testing
@testable import BilbyCore

@Suite("CaptionEngine")
struct CaptionEngineTests {

    /// The bar shows a new sentence once it has a draft, so this is when the
    /// reader first sees it, and its translation.
    @Test("a sentence can be drafted once it has two words")
    func draftsFromTwoWords() {
        var engine = CaptionEngine()
        _ = engine.consume(Utterance("People"))
        let one = engine.draftable
        _ = engine.consume(Utterance("People love"))
        let two = engine.draftable
        #expect(one == nil)
        #expect(two == "People love")
    }

    @Test("volatile speech drives the live line only")
    func volatileIsLiveOnly() {
        var engine = CaptionEngine()
        let events = engine.consume(Utterance("we are"))
        #expect(events == [.live("we are")])
    }

    /// The recogniser reports everything said since the session began, so the
    /// live line must show only what has not been turned into a caption yet —
    /// otherwise the first words of the meeting sit on screen for an hour.
    @Test("the live line shows only the unfinished sentence")
    func liveLineDropsWhatIsAlreadyShown() {
        var engine = CaptionEngine()
        _ = engine.consume(Utterance("We shipped it. "))
        let events = engine.consume(Utterance("We shipped it. And then we"))
        #expect(events == [.live("And then we")])
    }

    @Test("a completed clause becomes a line awaiting translation")
    func commitsClause() {
        var engine = CaptionEngine()
        let events = engine.consume(Utterance("we ship on Friday."))
        // The clause closed, so nothing is left being spoken.
        #expect(events == [.line(Line(id: 0, source: "we ship on Friday.",
                                      translation: nil, at: .zero)),
                           .live("")])
        #expect(engine.nextPending?.source == "we ship on Friday.")
    }

    @Test("resolving emits the translation")
    func emitsTranslation() {
        var engine = CaptionEngine()
        _ = engine.consume(Utterance("yes.", isFinal: true))
        let id = engine.nextPending!.id
        let events = engine.resolve(id, translation: "да")
        #expect(events == [.translated(id, "да")])
    }

    @Test("abandoning a line emits nothing")
    func silentOnFailure() {
        var engine = CaptionEngine()
        _ = engine.consume(Utterance("yes.", isFinal: true))
        let events = engine.resolve(engine.nextPending!.id, translation: nil)
        #expect(events.isEmpty)
    }
}
