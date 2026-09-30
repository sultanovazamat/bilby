import BilbyCore
import Testing

@testable import BilbySources

@Suite("Running transcript")
struct RunningTranscriptTests {
    @Test("a rollover flushes a short unfinished tail once without replaying completed clauses")
    func rolloverFlushesOnlyTail() {
        let running = RunningTranscript()
        _ = running.observe("A finished sentence. so far", pause: nil)
        #expect(!running.isAtBoundary)
        #expect(running.finish("A finished sentence. so far") == "so far")
        #expect(running.finish() == "")
        #expect(running.isAtBoundary)
    }

    @Test("words produced while draining the recognizer are included in the final tail")
    func finishIncludesLastWords() {
        let running = RunningTranscript()
        _ = running.observe("A finished sentence. One last", pause: nil)
        #expect(running.finish("A finished sentence. One last thought.") == "One last thought.")
        #expect(running.finish() == "")
    }

    @Test("recognition rolls over at boundaries after two minutes and always by three minutes")
    func boundedRecognitionWindow() {
        #expect(!RecognitionWindow.shouldReset(elapsed: 119, atBoundary: true))
        #expect(!RecognitionWindow.shouldReset(elapsed: 120, atBoundary: false))
        #expect(RecognitionWindow.shouldReset(elapsed: 120, atBoundary: true))
        #expect(RecognitionWindow.shouldReset(elapsed: 180, atBoundary: false))
    }

    @Test("repeated identical sentences across recognition windows are neither lost nor repeated")
    func boundariesResetClauseState() {
        let running = RunningTranscript()
        var engine = CaptionEngine()
        var emitted = 0
        for index in 0..<2_000 {
            let tail = running.observe("The same sentence.", pause: nil).tail
            for event in engine.consume(Utterance(tail, isFinal: false, at: .seconds(index))) {
                if case .line = event { emitted += 1 }
            }
            let final = running.finish("The same sentence.")
            #expect(final.isEmpty)
            for event in engine.consume(Utterance(final, isFinal: true, at: .seconds(index))) {
                if case .line = event { emitted += 1 }
            }
            running.reset()
        }
        #expect(emitted == 2_000)
        #expect(engine.transcript.lines.count == 500)
        #expect(engine.transcript.lines.first?.id == 1_500)
    }

    @Test("hard rollovers preserve all words when a speaker never pauses or punctuates")
    func continuousSpeechAcrossWindows() {
        let running = RunningTranscript()
        var engine = CaptionEngine()
        var expected: [String] = []
        var actual: [String] = []
        for window in 0..<4 {
            var whole: [String] = []
            for index in 0..<110 {
                let word = "word\(window)x\(index)"
                whole.append(word)
                expected.append(word)
                let tail = running.observe(whole.joined(separator: " "), pause: nil).tail
                for event in engine.consume(Utterance(tail, isFinal: false, at: .zero)) {
                    if case .line(let line) = event { actual += line.source.split(separator: " ").map(String.init) }
                }
            }
            expected.append("last")
            let tail = running.finish(whole.joined(separator: " ") + " last")
            for event in engine.consume(Utterance(tail, isFinal: true, at: .zero)) {
                if case .line(let line) = event { actual += line.source.split(separator: " ").map(String.init) }
            }
            running.reset()
        }
        #expect(actual == expected)
    }
    @Test("a finished sentence is handed over once and then left behind")
    func closesFinishedSentences() {
        let running = RunningTranscript()
        #expect(running.observe("Hello there. And then we", pause: nil).tail == "Hello there. And then we")
        #expect(running.observe("Hello there. And then we should go.", pause: nil).tail == "And then we should go.")
        #expect(running.observe("Hello there. And then we should go. So", pause: nil).tail == "So")
    }

    @Test("a sentence still being spoken keeps growing")
    func unfinishedKeepsGrowing() {
        let running = RunningTranscript()
        #expect(running.observe("and what I am", pause: nil).tail == "and what I am")
        #expect(running.observe("and what I am hearing", pause: nil).tail == "and what I am hearing")
    }

    @Test("a transcript that no longer starts with what was closed starts over")
    func revisionStartsOver() {
        let running = RunningTranscript()
        _ = running.observe("Hello there. And then", pause: nil)
        // Dropping a fixed number of characters from reworded text cuts mid-word.
        #expect(running.observe("Hi there! And then", pause: nil).tail == "Hi there! And then")
    }

    @Test("a fragment too short to stand alone waits for its sentence instead of being lost")
    func shortFragmentWaits() {
        let running = RunningTranscript()
        _ = running.observe("Hello there. so far", pause: nil)
        #expect(running.close(fewest: 3) == nil)
        // Kept, not thrown away: it arrives with the rest of its sentence.
        #expect(
            running.observe("Hello there. so far has been positive.", pause: nil).tail == "so far has been positive.")
    }

    @Test("closing hands over what is left and does not hand it over twice")
    func closeOnPause() {
        let running = RunningTranscript()
        _ = running.observe("Hello there. And then we went", pause: nil)
        #expect(running.close(fewest: 3) == "And then we went")
        #expect(running.close(fewest: 3) == nil)
        // Speech resuming carries on from the close, not from the meeting.
        #expect(running.observe("Hello there. And then we went to the shop", pause: nil).tail == "to the shop")
    }

    @Test("a restarted recogniser starts the transcript over")
    func resetStartsOver() {
        let running = RunningTranscript()
        _ = running.observe("Hello there. And then we", pause: nil)
        running.reset()
        // The new recogniser begins from nothing, and so must this.
        #expect(running.observe("Something else entirely.", pause: nil).tail == "Something else entirely.")
    }

    @Test("what the core is handed stays the size of a sentence, not the meeting")
    func staysSmall() {
        let running = RunningTranscript()
        var whole = ""
        var longest = 0
        for index in 0..<400 {
            whole += "This is sentence number \(index). "
            longest = max(longest, running.observe(whole, pause: nil).tail.count)
        }
        #expect(whole.count > 10_000)
        #expect(longest < 200)
    }
}
