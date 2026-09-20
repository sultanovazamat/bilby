/// Drives a `CaptionEngine` over a live stream of recognition results.
///
/// Clauses are translated strictly one at a time. Concurrent translation would
/// finish out of order and force lines to be reshuffled on screen, which the
/// transcript forbids — so sequential is not a simplification, it is the design.
public struct CaptionSession: Sendable {
    private let translator: any Translating
    private let target: Language
    private let policy: ClauseBuffer.Policy
    /// How often the unfinished sentence may be retranslated. Translation
    /// costs 0.07 s, so this is about not thrashing, not about cost.
    private let draftInterval: Duration

    public init(
        translator: any Translating,
        target: Language,
        policy: ClauseBuffer.Policy = ClauseBuffer.Policy(),
        draftInterval: Duration = .milliseconds(400)
    ) {
        self.translator = translator
        self.target = target
        self.policy = policy
        self.draftInterval = draftInterval
    }

    public func events(from utterances: AsyncStream<Utterance>) -> AsyncStream<CaptionEvent> {
        AsyncStream { continuation in
            // Audio arriving is not progress. This is what did.
            let pulse = Pulse()
            let task = Task {
                // Owned by this task alone, so no lock and no actor are needed.
                var engine = CaptionEngine(policy: policy)

                var lastDraft = ""
                var lastDraftAt = ContinuousClock.now - .seconds(10)

                for await utterance in utterances {
                    pulse.heard()
                    for event in engine.consume(utterance) { continuation.yield(event) }

                    while let line = engine.nextPending {
                        pulse.translating(line.source)
                        let translation = try? await translator.translate(line.source, to: target)
                        pulse.translated()
                        for event in engine.resolve(line.id, translation: translation) {
                            continuation.yield(event)
                        }
                    }

                    // The words are recognised about 1.2 s before the model
                    // decides the sentence ended. Translating them now is what
                    // takes the reader's wait from 1.6 s down to under half.
                    if let draft = engine.draftable,
                       draft != lastDraft,
                       ContinuousClock.now - lastDraftAt >= draftInterval {
                        lastDraft = draft
                        lastDraftAt = ContinuousClock.now
                        pulse.translating(draft)
                        let text = try? await translator.translate(draft, to: target)
                        pulse.translated()
                        if let text { continuation.yield(.draft(text)) }
                    }
                }
                continuation.finish()
            }
            // The bar freezing in place is the one failure the user sees and
            // the log used to say nothing about.
            let watchdog = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    if let line = pulse.report(stage: "captions") { Log.write(line) }
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                watchdog.cancel()
            }
        }
    }
}
