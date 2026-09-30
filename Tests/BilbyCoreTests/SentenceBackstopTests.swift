import Testing

@testable import BilbyCore

@Suite("Sentence backstop")
struct SentenceBackstopTests {
    /// The recogniser used by the app reports a word only once it has heard
    /// 320 ms past it.
    private let lookahead = 0.32

    @Test("the recogniser's look-ahead is not silence")
    func lookaheadIsNotSilence() {
        // From a real run: "Good morning" had ended at 2.080 s, and
        // "everyone" was being said but not yet reported when 2.707 s of
        // audio had been heard.
        var backstop = SentenceBackstop(lookahead: lookahead)
        let ended = backstop.ends(heard: 2.707, lastWordEnd: 2.080)
        #expect(!ended)
    }

    @Test("a hesitation in the middle of a sentence does not end it")
    func hesitation() {
        var backstop = SentenceBackstop(lookahead: lookahead)
        let ended = backstop.ends(heard: 10 + lookahead + 0.7, lastWordEnd: 10)
        #expect(!ended)
    }

    @Test("a real stop ends a sentence the model never punctuated")
    func realStop() {
        var backstop = SentenceBackstop(lookahead: lookahead)
        // Just past the threshold, so floating-point rounding cannot decide it.
        let ended = backstop.ends(heard: 10 + lookahead + SentenceBackstop.silence + 0.05, lastWordEnd: 10)
        #expect(ended)
    }

    @Test("one stop ends one sentence, and the next word starts another")
    func oncePerStop() {
        var backstop = SentenceBackstop(lookahead: lookahead)
        let stop = 10 + lookahead + SentenceBackstop.silence + 0.05
        let first = backstop.ends(heard: stop, lastWordEnd: 10)
        let again = backstop.ends(heard: stop + 0.05, lastWordEnd: 10)
        let later = backstop.ends(heard: stop + 2, lastWordEnd: 10)
        let next = backstop.ends(heard: 14 + lookahead + SentenceBackstop.silence + 0.05, lastWordEnd: 14)
        #expect(first)
        #expect(!again)
        #expect(!later)
        #expect(next)
    }

    @Test("nothing ends before anything was said")
    func beforeFirstWord() {
        var backstop = SentenceBackstop(lookahead: lookahead)
        let ended = backstop.ends(heard: 30, lastWordEnd: 0)
        #expect(!ended)
    }
}
