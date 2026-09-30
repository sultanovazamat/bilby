import Foundation

/// Ends a sentence the recogniser never punctuated, once the speaker has
/// clearly stopped.
///
/// The model's own full stop is the sentence boundary. It lands within a
/// second of the speaker stopping, and every rule that fired sooner cut
/// sentences mid-phrase: a threshold learned from the speaker's gaps ended
/// 24 "sentences" out of 13 in a measured run, at commas and hesitations,
/// and the translator was handed the fragments. This is only for speech the
/// model leaves unpunctuated, so it waits well past the model.
///
/// Silence is counted from what the recogniser has had the chance to hear.
/// It reports a word only once it has heard its look-ahead past it, so the
/// time since its last word always includes speech it has not reported yet:
/// counting that as silence ended "Good morning" while "everyone" was being
/// said.
public struct SentenceBackstop: Sendable {
    /// Silence past the look-ahead that ends an unpunctuated sentence:
    /// longer than the model takes to punctuate, and than a hesitation.
    public static let silence: TimeInterval = 1.2

    private let lookahead: TimeInterval
    /// Where the last word before the last stop ended, so one stop ends one
    /// sentence rather than one every time it is asked.
    private var endedAfter: TimeInterval = 0

    public init(lookahead: TimeInterval) {
        self.lookahead = lookahead
    }

    /// Whether the speaker has stopped. `heard` is the audio the recogniser
    /// has been given and `lastWordEnd` where its last word ended, both on
    /// its own clock. True once per stop.
    public mutating func ends(heard: TimeInterval, lastWordEnd: TimeInterval) -> Bool {
        guard lastWordEnd > 0, lastWordEnd > endedAfter,
            heard - lookahead - lastWordEnd >= Self.silence
        else { return false }
        endedAfter = lastWordEnd
        return true
    }
}
