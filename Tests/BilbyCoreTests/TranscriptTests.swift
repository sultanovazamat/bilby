import Testing
@testable import BilbyCore

@Suite("Transcript")
struct TranscriptTests {

    @Test("hands out increasing ids and queues lines for translation")
    func appendsInOrder() {
        var transcript = Transcript()
        let first = transcript.append(Clause(text: "one", at: .zero))
        let second = transcript.append(Clause(text: "two", at: .zero))
        #expect(first.id == 0)
        #expect(second.id == 1)
        #expect(transcript.nextPending?.id == 0)
    }

    @Test("attaches a translation once")
    func resolvesOnce() {
        var transcript = Transcript()
        let line = transcript.append(Clause(text: "one", at: .zero))
        let attached = transcript.resolve(line.id, translation: "один")
        #expect(attached)
        #expect(transcript.lines[0].translation == "один")
    }

    @Test("refuses to rewrite a line that is already on screen")
    func neverRewrites() {
        var transcript = Transcript()
        let line = transcript.append(Clause(text: "one", at: .zero))
        transcript.resolve(line.id, translation: "один")
        let again = transcript.resolve(line.id, translation: "ЕДИН")
        #expect(again == false)
        #expect(transcript.lines[0].translation == "один")
    }

    @Test("a failed translation does not block the line behind it")
    func failureDoesNotBlock() {
        var transcript = Transcript()
        let first = transcript.append(Clause(text: "one", at: .zero))
        _ = transcript.append(Clause(text: "two", at: .zero))
        transcript.resolve(first.id, translation: nil)
        #expect(transcript.lines[0].translation == nil)
        #expect(transcript.nextPending?.source == "two")
    }
}
