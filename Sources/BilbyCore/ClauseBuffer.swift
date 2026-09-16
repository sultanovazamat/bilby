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
    /// Characters of the current utterance already turned into clauses.
    private var emitted = 0

    public init(policy: Policy = Policy()) { self.policy = policy }

    /// Feeds one recognition result and returns the clauses it completed.
    public mutating func consume(_ utterance: Utterance) -> [Clause] {
        // Text already shown is never revisited. Real finals reword what the
        // volatile results said — one turned "off site" into "of site" — but a
        // caption the reader has already started reading must not change, and
        // re-emitting it would put the same line on screen twice.
        let characters = Array(utterance.text)
        var rest = characters.dropFirst(min(emitted, characters.count))
        var clauses: [Clause] = []

        while let cut = rest.firstIndex(where: { policy.terminators.contains($0) }) {
            clauses.append(take(&rest, upTo: cut, at: utterance.at))
        }

        if utterance.isFinal {
            clauses.append(Clause(text: String(rest).trimmed, at: utterance.at))
            emitted = 0
        } else if String(rest).wordCount >= policy.maxWords,
                  let cut = rest.lastIndex(where: { policy.softBreaks.contains($0) }) {
            clauses.append(take(&rest, upTo: cut, at: utterance.at))
        }

        return clauses.filter { !$0.text.isEmpty }
    }


    private mutating func take(
        _ rest: inout ArraySlice<Character>, upTo cut: Int, at time: Duration
    ) -> Clause {
        let piece = rest[rest.startIndex...cut]
        emitted += piece.count
        rest = rest[rest.index(after: cut)...]
        return Clause(text: String(piece).trimmed, at: time)
    }
}
