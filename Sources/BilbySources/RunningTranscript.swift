import Foundation

/// Parakeet reports the whole session transcript on every update,
/// not the current sentence. This subtracts what is already closed, so the core
/// sees one utterance at a time instead of an ever-growing monologue.
final class RunningTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = ""
    private var latest = ""
    private var changedAt = ContinuousClock.now

    /// Reports what is new, and — when `pause` is given — the thought that a
    /// silence has just ended. Engines that emit punctuation pass `nil`:
    /// their full stops are a better boundary than any timing guess.
    func observe(_ whole: String, pause: Duration?) -> (finished: String?, tail: String) {
        lock.lock(); defer { lock.unlock() }

        var finished: String?
        if whole != latest {
            if let pause {
                let previous = tailOf(latest)
                // Four words: shorter fragments are rarely a whole thought, and
                // a stray "yeah" on its own line reads as noise.
                if ContinuousClock.now - changedAt >= pause,
                   previous.split(whereSeparator: \.isWhitespace).count >= 4 {
                    finished = previous
                    closed = latest
                }
            }
            latest = whole
            changedAt = ContinuousClock.now
        }
        return (finished, tailOf(whole))
    }

    /// Closes the current utterance and returns it.
    func close(_ whole: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let tail = tailOf(whole)
        closed = whole
        return tail
    }

    private func tailOf(_ whole: String) -> String {
        String(whole.dropFirst(min(closed.count, whole.count)))
            .trimmingCharacters(in: .whitespaces)
    }
}
