/// Decides when recognised speech is complete enough to translate.
///
/// You cannot translate English into Russian word by word: word order and case
/// depend on the whole clause. Cut too early and the translation is wrong; cut
/// too late and the captions lag. That trade-off is the feel of the product,
/// so it lives in one pure type that is tested against text, never audio.
public struct ClauseBuffer: Sendable {

    public struct Policy: Sendable {
        /// Always cut here.
        public var terminators: Set<Character> = [".", "!", "?", "…"]
        /// Cut here only once the clause is already long.
        public var softBreaks: Set<Character> = [",", ";", ":", "—"]
        /// Word count above which a soft break becomes a cut.
        public var maxWords: Int = 12

        public init() {}
    }

    private let policy: Policy
    /// The part of the current utterance already turned into clauses.
    private var shown = ""
    /// The words spoken since the last clause closed. Recognised long before
    /// the model commits to a full stop, so this is what a draft translates.
    public private(set) var pending = ""

    public init(policy: Policy = Policy()) { self.policy = policy }

    /// Feeds one recognition result and returns the clauses it completed.
    public mutating func consume(_ utterance: Utterance) -> [Clause] {
        // Utterance boundaries are detected by content, not by `isFinal`.
        // Finals arrive seconds late and are not forwarded at all, so relying
        // on them left `shown` stale and sliced the opening words off every
        // following sentence — "watch out" arrived as "ch out".
        var rest: Substring
        if utterance.text.hasPrefix(shown) {
            rest = utterance.text.dropFirst(shown.count)
        } else if zip(utterance.text, shown).prefix(while: ==).count >= shown.count / 2 {
            // Same sentence, reworded behind our back: one real result turned
            // "off site" into "of site". Keep what is on screen and take only
            // what is genuinely new.
            rest = utterance.text.dropFirst(min(shown.count, utterance.text.count))
        } else {
            shown = ""
            rest = utterance.text[...]
        }

        var clauses: [Clause] = []
        while let cut = rest.firstIndex(where: { policy.terminators.contains($0) }) {
            clauses.append(take(&rest, through: cut, at: utterance.at))
        }

        if utterance.isFinal {
            clauses.append(Clause(text: rest.trimmed, at: utterance.at))
            shown = ""
        } else if rest.wordCount >= policy.maxWords,
                  let cut = rest.lastIndex(where: { policy.softBreaks.contains($0) }) {
            clauses.append(take(&rest, through: cut, at: utterance.at))
        }

        pending = rest.trimmed

        // A lone "." is a clause by the rules above and nonsense on screen.
        return clauses.filter { $0.text.contains(where: \.isLetter) }
    }

    private mutating func take(
        _ rest: inout Substring, through cut: Substring.Index, at time: Duration
    ) -> Clause {
        let piece = rest[...cut]
        shown += piece
        rest = rest[rest.index(after: cut)...]
        return Clause(text: piece.trimmed, at: time)
    }
}
