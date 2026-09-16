import Testing
@testable import BilbyCore

@Suite("CaptionSession")
struct CaptionSessionTests {

    private func run(
        _ utterances: [Utterance], translator: EchoTranslator = EchoTranslator()
    ) async -> [CaptionEvent] {
        let session = CaptionSession(translator: translator, target: Language("ru"))
        var events: [CaptionEvent] = []
        for await event in session.events(from: stream(utterances)) { events.append(event) }
        return events
    }

    @Test("translations arrive in the order the lines were spoken")
    func keepsOrder() async {
        let events = await run([
            Utterance("one."), Utterance("one. two."), Utterance("one. two. three.")
        ])
        let translated = events.compactMap { if case .translated(_, let text) = $0 { text } else { nil } }
        #expect(translated == ["[ru] one.", "[ru] two.", "[ru] three."])
    }

    @Test("one failed translation does not stop the next line")
    func survivesTranslationFailure() async {
        let events = await run(
            [Utterance("one."), Utterance("one. two.")],
            translator: EchoTranslator(failOn: ["one."])
        )
        let translated = events.compactMap { if case .translated(_, let text) = $0 { text } else { nil } }
        #expect(translated == ["[ru] two."])
    }

    /// Measured on a real call: words are recognised about 1.2 s before the
    /// model commits to a full stop. Waiting for it put the reader 1.6 s
    /// behind the speaker, so the unfinished sentence is translated too.
    @Test("the sentence still being spoken is translated before it ends")
    func draftsUnfinishedSpeech() async {
        let events = await run([Utterance("we should ship the beta")])
        let drafts = events.compactMap { if case .draft(let text) = $0 { text } else { nil } }
        #expect(drafts == ["[ru] we should ship the beta"])
    }

    @Test("a fragment too short to translate produces no draft")
    func waitsForEnoughWords() async {
        let events = await run([Utterance("we")])
        #expect(!events.contains { if case .draft = $0 { true } else { false } })
    }

    @Test("every line is shown before its translation exists")
    func showsSourceFirst() async {
        let events = await run([Utterance("one.", isFinal: true)])
        let lineIndex = events.firstIndex { if case .line = $0 { true } else { false } }
        let translatedIndex = events.firstIndex { if case .translated = $0 { true } else { false } }
        #expect(lineIndex! < translatedIndex!)
    }
}
