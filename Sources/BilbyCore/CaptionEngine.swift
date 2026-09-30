/// The caption state machine: recognition results in, screen events out.
///
/// Deliberately synchronous and free of I/O. Every decision about what the user
/// sees is made here, which is why the whole product can be tested with strings.
public struct CaptionEngine: Sendable {
    public private(set) var transcript = Transcript()
    private var buffer: ClauseBuffer

    public init(policy: ClauseBuffer.Policy = ClauseBuffer.Policy()) {
        buffer = ClauseBuffer(policy: policy)
    }

    /// The oldest line still waiting to be translated.
    public var nextPending: Line? { transcript.nextPending }

    /// The sentence still being spoken, if it is worth translating yet.
    ///
    /// Capped: a draft is a glance at what is being said now, and translating
    /// more than a line of it costs time the reader does not have.
    public var draftable: String? {
        let words = buffer.pending.split(whereSeparator: \.isWhitespace)
        // Two, not three: the bar moves on to a sentence once it has a draft,
        // and waiting for a third word held every sentence start back by a
        // quarter of a second (measured, 1.14 s against 0.89 s). Two words
        // are usually a subject and its verb — "Я хочу", "Люди любят" — and
        // a draft is replaced within half a second anyway.
        guard words.count >= 2 else { return nil }
        return words.suffix(20).joined(separator: " ")
    }

    public mutating func consume(_ utterance: Utterance) -> [CaptionEvent] {
        var events: [CaptionEvent] = []
        for clause in buffer.consume(utterance) {
            events.append(.line(transcript.append(clause)))
        }
        // The live line is the sentence being spoken — what the buffer has not
        // closed yet. Showing the utterance itself put the whole session on
        // screen, because the recogniser reports everything said so far.
        if !utterance.isFinal { events.append(.live(buffer.pending)) }
        return events
    }

    /// Settles a pending line. `nil` abandons it silently.
    public mutating func resolve(_ id: Line.ID, translation: String?) -> [CaptionEvent] {
        guard transcript.resolve(id, translation: translation), let translation else { return [] }
        return [.translated(id, translation)]
    }
}
