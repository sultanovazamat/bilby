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
    private var utterances = 0
    private var lines = 0
    private var failure: String?

    public init() {}

    public func audio(_ count: Int) { mutate { frames += count } }
    public func heardSomething() { mutate { utterances += 1 } }
    public func committedLine() { mutate { lines += 1 } }
    public func failed(_ reason: String) { mutate { failure = reason } }

    public func reset() {
        mutate { frames = 0; utterances = 0; lines = 0; failure = nil }
    }

    /// The first stage that is empty. `StatusText` turns it into a sentence.
    public enum State: Equatable, Sendable {
        case failed(String)
        case noAudio
        case noSpeech(frames: Int)
        case noSentence(utterances: Int)
        case flowing(lines: Int)
    }

    public var state: State {
        lock.lock(); defer { lock.unlock() }
        if let failure { return .failed(failure) }
        if frames == 0 { return .noAudio }
        if utterances == 0 { return .noSpeech(frames: frames) }
        if lines == 0 { return .noSentence(utterances: utterances) }
        return .flowing(lines: lines)
    }

    private func mutate(_ change: () -> Void) {
        lock.lock(); change(); lock.unlock()
    }
}
