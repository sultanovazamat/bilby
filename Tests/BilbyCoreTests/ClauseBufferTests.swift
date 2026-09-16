import Testing
@testable import BilbyCore

@Suite("ClauseBuffer")
struct ClauseBufferTests {

    /// `#expect` cannot call mutating members, so tests feed the buffer first.
    private func clauses(_ texts: [Utterance], policy: ClauseBuffer.Policy = .init()) -> [[String]] {
        var buffer = ClauseBuffer(policy: policy)
        return texts.map { buffer.consume($0).map(\.text) }
    }

    @Test("waits while a sentence is still being spoken")
    func holdsIncompleteSpeech() {
        let got = clauses([Utterance("so let's"), Utterance("so let's circle back")])
        #expect(got == [[], []])
    }

    @Test("cuts on a terminator")
    func cutsOnTerminator() {
        #expect(clauses([Utterance("we ship on Friday. and then")]) == [["we ship on Friday."]])
    }

    @Test("does not repeat a clause it already emitted")
    func emitsEachClauseOnce() {
        let got = clauses([
            Utterance("we ship on Friday."),
            Utterance("we ship on Friday. and then we"),
        ])
        #expect(got == [["we ship on Friday."], []])
    }

    @Test("cuts several sentences arriving in one update")
    func cutsSeveralSentences() {
        #expect(clauses([Utterance("yes. no. maybe")]) == [["yes.", "no."]])
    }

    @Test("a final utterance releases the tail without punctuation")
    func finalReleasesTail() {
        #expect(clauses([Utterance("no punctuation here", isFinal: true)])
                == [["no punctuation here"]])
    }

    @Test("a long clause is cut at a comma rather than left hanging")
    func cutsLongClauseAtSoftBreak() {
        let text = "one two three four five six seven eight nine ten, eleven twelve"
        #expect(clauses([Utterance(text)])
                == [["one two three four five six seven eight nine ten,"]])
    }

    @Test("a short clause is never cut at a comma")
    func keepsShortClauseWhole() {
        #expect(clauses([Utterance("well, maybe")]) == [[]])
    }

    @Test("never shows a clause twice when the transcriber rewords it")
    func ignoresRevisionOfShownText() {
        let got = clauses([
            Utterance("we ship on Friday. and then we"),
            Utterance("we shipped."),
        ])
        #expect(got == [["we ship on Friday."], []])
    }

    /// Taken from a real run: the volatile result already carries the full stop
    /// and arrives ~0.2s after the words; the final arrives seconds later with
    /// different wording. Only one line may reach the screen.
    @Test("a slow, reworded final does not duplicate the volatile clause")
    func finalDoesNotDuplicate() {
        let got = clauses([
            Utterance("We should ship the beta before the off site."),
            Utterance("We should ship the beta before the of site.", isFinal: true),
        ])
        #expect(got == [["We should ship the beta before the off site."], []])
    }

    @Test("starts a new utterance cleanly after a final one")
    func resetsAfterFinal() {
        let got = clauses([
            Utterance("first sentence", isFinal: true),
            Utterance("second one", isFinal: true),
        ])
        #expect(got == [["first sentence"], ["second one"]])
    }
}
