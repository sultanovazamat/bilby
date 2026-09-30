import Synchronization
import Testing

@testable import BilbyCore

@Suite("CaptionSession")
struct CaptionSessionTests {
    private actor StalledTranslator: Translating {
        private var waiting: CheckedContinuation<String, Never>?
        private let started: AsyncStream<Void>.Continuation

        init(started: AsyncStream<Void>.Continuation) { self.started = started }

        func translate(_ text: String, to language: Language) async throws -> String {
            await withCheckedContinuation { continuation in
                waiting = continuation
                started.yield(())
                started.finish()
            }
        }

        func release() {
            waiting?.resume(returning: "Finished after Stop")
            waiting = nil
        }
    }

    @Test("Stop cancels capture immediately even while translation ignores task cancellation")
    func stopDoesNotWaitForTranslation() async {
        let cancellation = SessionCancellation()
        let captureStopped = Mutex(false)
        cancellation.onCancel { captureStopped.withLock { $0 = true } }
        let started = AsyncStream<Void>.makeStream()
        let translator = StalledTranslator(started: started.continuation)
        let session = CaptionSession(
            translator: translator, target: Language("es"), cancellation: cancellation)
        let events = session.events(from: stream([Utterance("Private sentence.", isFinal: true)]))
        for await _ in started.stream { break }
        cancellation.cancel()
        // The translator is still suspended. Stopping capture must not need
        // its cooperation, and the event stream must already be finished.
        #expect(captureStopped.withLock { $0 })
        var received: [CaptionEvent] = []
        for await event in events { received.append(event) }
        #expect(!received.contains { if case .translated = $0 { true } else { false } })
        await translator.release()
    }

    @Test("a reusable session gets an independent cancellation handle for each stream")
    func independentDefaultCancellation() async {
        let session = CaptionSession(translator: EchoTranslator(), target: Language("es"))
        for _ in 0..<2 {
            var translations = 0
            for await event in session.events(from: stream([Utterance("One sentence.", isFinal: true)])) {
                if case .translated = event { translations += 1 }
            }
            #expect(translations == 1)
        }
    }

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
            Utterance("one."), Utterance("one. two."), Utterance("one. two. three."),
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

    @Test("a stalled UI gets a bounded backlog and an explicit stop notification")
    func stopsWhenDisplayStopsConsuming() async {
        let notice = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let session = CaptionSession(
            translator: EchoTranslator(), target: Language("es"),
            onOverflow: {
                notice.continuation.yield(())
                notice.continuation.finish()
            })
        let events = session.events(from: stream((0..<2_000).map { Utterance("Sentence \($0).", isFinal: true) }))
        // Deliberately leave events unconsumed until the producer reports overload.
        for await _ in notice.stream { break }
        var received: [CaptionEvent] = []
        for await event in events { received.append(event) }
        #expect(received.count == 512)
        let lines = received.compactMap { if case .line(let line) = $0 { line.id } else { nil } }
        #expect(lines == Array(0..<256))
    }
}
