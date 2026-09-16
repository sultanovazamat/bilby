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

    public mutating func consume(_ utterance: Utterance) -> [CaptionEvent] {
        var events: [CaptionEvent] = []
        if !utterance.isFinal { events.append(.live(utterance.text)) }
        for clause in buffer.consume(utterance) {
            events.append(.line(transcript.append(clause)))
        }
        return events
    }

    /// Settles a pending line. `nil` abandons it silently.
    public mutating func resolve(_ id: Line.ID, translation: String?) -> [CaptionEvent] {
        guard transcript.resolve(id, translation: translation), let translation else { return [] }
        return [.translated(id, translation)]
    }
}
