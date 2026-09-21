import BilbyCore
import Foundation

/// Counts what actually reaches each stage of the pipeline.
///
/// A caption bar that shows nothing looks identical whether no one is
/// speaking, the tap is dead, recognition failed or translation failed. This
/// makes the difference visible instead of leaving the user to guess — and it
/// exists because a silent failure cost an afternoon.
public final class Diagnostics: @unchecked Sendable {
    private let lock = NSLock()
    private var frames = 0
    private var firstFrameAt: ContinuousClock.Instant?
    private var utterances = 0
    private var lines = 0
    private var translations = 0
    private var failure: TapFailure?

    public init() {}

    public func audio(_ count: Int) {
        mutate {
            if firstFrameAt == nil { firstFrameAt = ContinuousClock.now }
            frames += count
        }
    }

    /// When the first buffer actually arrived.
    ///
    /// An aggregate device around a process tap took ten seconds to deliver
    /// anything, measured, and the audio clock starts at that first buffer.
    /// Timing captions from when the session was asked for counted that wait
    /// as if it were delay in the pipeline, and made a 0.4 s pipeline look
    /// like a twelve-second one.
    public var startedAt: ContinuousClock.Instant? {
        lock.lock(); defer { lock.unlock() }
        return firstFrameAt
    }
    public func heardSomething() { mutate { utterances += 1 } }
    public func committedLine() { mutate { lines += 1 } }
    public func translated() { mutate { translations += 1 } }
    public func failed(_ failure: TapFailure) { mutate { self.failure = failure } }

    public func reset() {
        mutate {
            frames = 0; utterances = 0; lines = 0; translations = 0
            failure = nil; firstFrameAt = nil
        }
    }

    /// The first stage that is empty. `StatusText` turns it into a sentence.
    public enum State: Equatable, Sendable {
        case failed(TapFailure)
        case noAudio
        case noSpeech(frames: Int)
        case noSentence(utterances: Int)
        /// Sentences are arriving and none of them is coming back
        /// translated. CaptionSession discards translation errors by
        /// design, so this state is the only sign a user ever gets:
        /// before it, a missing language pair showed as English
        /// captions, forever, with the menu reporting everything fine.
        case noTranslation(lines: Int)
        case flowing(lines: Int)
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        if let failure { return .failed(failure) }
        if frames == 0 { return .noAudio }
        if utterances == 0 { return .noSpeech(frames: frames) }
        if lines == 0 { return .noSentence(utterances: utterances) }
        // Three, not one: the first line is on screen while its translation
        // is still in flight, and two leaves room for one slow pair. Three
        // sentences with nothing back is not a slow pair.
        if translations == 0, lines >= 3 { return .noTranslation(lines: lines) }
        return .flowing(lines: lines)
    }

    private func mutate(_ change: () -> Void) {
        lock.lock(); change(); lock.unlock()
    }
}
