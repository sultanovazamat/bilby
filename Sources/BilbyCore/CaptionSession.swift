/// Drives a `CaptionEngine` over a live stream of recognition results.
///
/// Clauses are translated strictly one at a time. Concurrent translation would
/// finish out of order and force lines to be reshuffled on screen, which the
/// transcript forbids — so sequential is not a simplification, it is the design.
public struct CaptionSession: Sendable {
    private let translator: any Translating
    private let target: Language
    private let policy: ClauseBuffer.Policy

    public init(
        translator: any Translating,
        target: Language,
        policy: ClauseBuffer.Policy = ClauseBuffer.Policy()
    ) {
        self.translator = translator
        self.target = target
        self.policy = policy
    }

    public func events(from utterances: AsyncStream<Utterance>) -> AsyncStream<CaptionEvent> {
        AsyncStream { continuation in
            let task = Task {
                // Owned by this task alone, so no lock and no actor are needed.
                var engine = CaptionEngine(policy: policy)

                for await utterance in utterances {
                    for event in engine.consume(utterance) { continuation.yield(event) }

                    while let line = engine.nextPending {
                        let translation = try? await translator.translate(line.source, to: target)
                        for event in engine.resolve(line.id, translation: translation) {
                            continuation.yield(event)
                        }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
