import Testing
@testable import BilbyCore

@Suite("ClauseBuffer")
struct ClauseBufferTests {

    /// The safety-net cut is a last resort in production, so tests that are
    /// about it say so explicitly rather than riding on the default.
    private static var shortPolicy: ClauseBuffer.Policy {
        var policy = ClauseBuffer.Policy()
        policy.maxWords = 12
        return policy
    }

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
        #expect(clauses([Utterance(text)], policy: Self.shortPolicy)
                == [["one two three four five six seven eight nine ten,"]])
    }

    /// Parakeet emits no punctuation at all. Waiting for a full stop that never
    /// arrives let one "unfinished sentence" grow to the length of a monologue,
    /// which was then retranslated several times a second.
    @Test("unpunctuated speech is still cut into lines")
    func cutsSpeechWithoutPunctuation() {
        let text = "so i just thought it would be really fun to go and try to build "
            + "this even if it did not work out"
        let got = clauses([Utterance(text)], policy: Self.shortPolicy)
        #expect(got.first?.count == 1)
        #expect(got.first?.first?.split(whereSeparator: \.isWhitespace).count == 12)
    }

    @Test("a short clause is never cut at a comma")
    func keepsShortClauseWhole() {
        #expect(clauses([Utterance("well, maybe")]) == [[]])
    }

    /// From a real run: finals are never forwarded, so a new sentence has to
    /// be recognised by content or its opening words are sliced off —
    /// "watch out, Dwight" arrived on screen as "ch out, Dwight".
    @Test("does not slice the start off the next sentence")
    func detectsANewUtterance() {
        let got = clauses([
            Utterance("It appears that the website has become alive."),
            Utterance("watch out, Dwight."),
        ])
        #expect(got == [["It appears that the website has become alive."],
                        ["watch out, Dwight."]])
    }

    @Test("a clause with no words never reaches the screen")
    func dropsPunctuationOnlyClauses() {
        #expect(clauses([Utterance(". .")]) == [[]])
    }

    @Test("text sharing almost nothing with the screen is a new sentence")
    func treatsUnrelatedTextAsNewUtterance() {
        let got = clauses([
            Utterance("we ship on Friday. and then we"),
            Utterance("we shipped."),
        ])
        #expect(got == [["we ship on Friday."], ["we shipped."]])
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

    @Test("a sentence released by a pause is not still pending afterwards")
    func finalLeavesNothingPending() {
        var buffer = ClauseBuffer()
        let clauses = buffer.consume(Utterance("and then we went to the shop", isFinal: true))
        #expect(clauses.map(\.text) == ["and then we went to the shop"])
        // Otherwise the live line goes on showing a sentence already shown,
        // and the draft translator keeps paying to translate it.
        #expect(buffer.pending.isEmpty)
    }
}
