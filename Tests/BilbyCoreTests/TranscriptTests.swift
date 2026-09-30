import Testing

@testable import BilbyCore

@Suite("Transcript")
struct TranscriptTests {

    @Test("retains only the latest 500 lines and their pending translations")
    func boundsHistoryAndPendingWork() {
        var transcript = Transcript()
        for index in 0..<2_000 {
            let line = transcript.append(Clause(text: "Sentence \(index).", at: .seconds(index)))
            #expect(line.id == index)
        }
        #expect(transcript.lines.count == 500)
        #expect(transcript.lines.first?.id == 1_500)
        #expect(transcript.lines.last?.id == 1_999)
        let stale = transcript.resolve(0, translation: "No longer displayed")
        #expect(!stale)
        var translated = 0
        while let pending = transcript.nextPending {
            let resolved = transcript.resolve(pending.id, translation: "Translated")
            #expect(resolved)
            translated += 1
        }
        #expect(translated == 500)
        #expect(transcript.lines.allSatisfy { $0.translation == "Translated" })
    }

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
