import Testing

@testable import BilbySources

@Suite("Running transcript")
struct RunningTranscriptTests {
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

    @Test("closing hands over what is left and does not hand it over twice")
    func closeOnPause() {
        let running = RunningTranscript()
        _ = running.observe("Hello there. And then we went", pause: nil)
        #expect(running.close() == "And then we went")
        #expect(running.close() == "")
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
