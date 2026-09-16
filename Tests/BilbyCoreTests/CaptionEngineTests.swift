import Testing
@testable import BilbyCore

@Suite("CaptionEngine")
struct CaptionEngineTests {

    @Test("volatile speech drives the live line only")
    func volatileIsLiveOnly() {
        var engine = CaptionEngine()
        let events = engine.consume(Utterance("we are"))
        #expect(events == [.live("we are")])
    }

    @Test("a completed clause becomes a line awaiting translation")
    func commitsClause() {
        var engine = CaptionEngine()
        let events = engine.consume(Utterance("we ship on Friday."))
        #expect(events.count == 2)
        #expect(events.first == .live("we ship on Friday."))
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
