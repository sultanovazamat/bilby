import BilbyCore
import Testing

@testable import BilbyUI

@Suite("Caption model")
@MainActor
struct CaptionModelTests {
    @Test("a finished sentence stays with its translation until the next one has a draft")
    func pairSwitchesTogether() throws {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for event in engine.consume(Utterance("We need to talk about the runway. And")) { model.apply(event) }
        #expect(model.pair?.source == "We need to talk about the runway.")
        #expect(model.pair?.translation == nil)

        let line = try #require(model.latest)
        for event in engine.resolve(line.id, translation: "Нам нужно поговорить о запасе денег.") { model.apply(event) }
        #expect(
            model.pair
                == CaptionModel.Pair(
                    source: "We need to talk about the runway.", translation: "Нам нужно поговорить о запасе денег.",
                    settled: true))

        model.apply(.live("And then we should"))
        #expect(model.pair?.source == "We need to talk about the runway.")

        model.apply(.draft("А потом нам следует"))
        #expect(
            model.pair == CaptionModel.Pair(source: "And then we should", translation: "А потом нам следует", settled: false))
    }

    @Test("a draft follows its sentence when the sentence closes")
    func draftCarriesOver() throws {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for event in engine.consume(Utterance("Let us begin now")) { model.apply(event) }
        model.apply(.draft("Давайте начнём"))
        for event in engine.consume(Utterance("Let us begin now. So")) { model.apply(event) }
        #expect(model.pair == CaptionModel.Pair(source: "Let us begin now.", translation: "Давайте начнём", settled: false))

        let line = try #require(model.latest)
        for event in engine.resolve(line.id, translation: "Давайте начнём.") { model.apply(event) }
        #expect(model.pair == CaptionModel.Pair(source: "Let us begin now.", translation: "Давайте начнём.", settled: true))
    }

    @Test("the first words show alone, before any translation exists")
    func firstWords() {
        let model = CaptionModel()
        model.apply(.live("Good morning everyone"))
        #expect(model.pair == CaptionModel.Pair(source: "Good morning everyone", translation: nil, settled: false))
    }

    @Test("history keeps the last five hundred sentences")
    func historyIsCapped() {
        let model = CaptionModel()
        var engine = CaptionEngine()
        for index in 0..<505 {
            for event in engine.consume(Utterance("Sentence \(index).", isFinal: true)) { model.apply(event) }
        }
        #expect(model.lines.count == CaptionModel.historyLimit)
        #expect(model.lines.first?.source == "Sentence 5.")
        #expect(model.lines.last?.source == "Sentence 504.")
    }

    @Test("the status line clears when words arrive and when the session ends")
    func statusClears() {
        let model = CaptionModel()
        model.status = "Getting ready…"
        model.apply(.live(""))
        #expect(model.status == "Getting ready…")
        model.apply(.live("Hello"))
        #expect(model.status == nil)
        model.status = "Listening to Zoom…"
        model.clear()
        #expect(model.status == nil)
    }
}
