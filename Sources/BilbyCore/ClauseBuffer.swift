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
        /// Last-resort cut for speech that never pauses. Boundaries should
        /// come from the speaker stopping, not from a counter — cutting every
        /// twelve words split "it wasn't" from "really that risky" and put the
        /// opposite meaning on screen.
        public var maxWords: Int = 25

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
        } else if rest.wordCount >= policy.maxWords {
            // Prefer a comma, but cut regardless: Parakeet emits no punctuation
            // at all, and waiting for a full stop that never comes let a single
            // "unfinished sentence" grow to the length of a whole monologue.
            let cut = rest.lastIndex(where: { policy.softBreaks.contains($0) })
                ?? boundary(in: rest, afterWords: policy.maxWords)
            if let cut { clauses.append(take(&rest, through: cut, at: utterance.at)) }
        }

        pending = rest.trimmed

        // A lone "." is a clause by the rules above and nonsense on screen.
        return clauses.filter { $0.text.contains(where: \.isLetter) }
    }

    /// The end of the nth word, so a cut lands between words rather than
    /// inside one.
    private func boundary(in text: Substring, afterWords count: Int) -> Substring.Index? {
        var words = 0
        var index = text.startIndex
        var inWord = false
        while index < text.endIndex {
            if text[index].isWhitespace {
                if inWord { words += 1; if words >= count { return index } }
                inWord = false
            } else {
                inWord = true
            }
            index = text.index(after: index)
        }
        return nil
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
