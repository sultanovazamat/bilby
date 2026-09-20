import BilbyCore
import Foundation

/// Parakeet reports the whole session transcript on every update — its cache
/// only ever grows — so this closes each sentence once it has been handed
/// over, and the core sees one sentence at a time instead of an ever-growing
/// monologue.
///
/// Without it the clause buffer prefix-compares the entire meeting several
/// times a second, and a reworded early word makes it decide the text is new
/// and replay every sentence since the meeting began.
final class RunningTranscript: @unchecked Sendable {
    private static let terminators = ClauseBuffer.Policy().terminators

    private let lock = NSLock()
    /// The part of the transcript already passed on, up to and including the
    /// last sentence the recogniser finished.
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
                let previous = rest(of: latest)
                // Four words: shorter fragments are rarely a whole thought, and
                // a stray "yeah" on its own line reads as noise.
                if ContinuousClock.now - changedAt >= pause,
                    previous.split(whereSeparator: \.isWhitespace).count >= 4
                {
                    finished = String(previous)
                    closed = latest
                }
            }
            latest = whole
            changedAt = ContinuousClock.now
        }

        let remainder = rest(of: whole)
        // Everything up to the last finished sentence is the core's business
        // now, not ours.
        if let end = remainder.lastIndex(where: { Self.terminators.contains($0) }) {
            closed = String(whole[..<remainder.index(after: end)])
        }
        return (finished, remainder.trimmingCharacters(in: .whitespaces))
    }

    /// What has not been passed on yet. A transcript that no longer starts
    /// with what was closed has been reworded behind our back, and dropping a
    /// fixed number of characters from it would cut mid-word.
    private func rest(of whole: String) -> Substring {
        guard whole.hasPrefix(closed) else {
            closed = ""
            return whole[...]
        }
        return whole.dropFirst(closed.count)
    }
}
