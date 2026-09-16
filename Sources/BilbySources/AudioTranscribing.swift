import AVFoundation
import BilbyCore

/// A speech recogniser. The port lives here rather than in the core because it
/// speaks in audio buffers, and the core must never see a framework type.
///
/// Two implementations exist so they can be compared on the same call rather
/// than argued about.
public protocol AudioTranscribing: Sendable {
    func utterances(
        from source: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>
    ) -> AsyncStream<Utterance>

    /// Loads the models before anyone asks for captions.
    ///
    /// Unified takes 50 s on a cold start. Doing that inside the listening
    /// task meant the audio tap opened fifty seconds after the user pressed
    /// play — by which time the app they wanted to hear had stopped playing.
    /// CoreML caches the compiled result, so warming up once makes the real
    /// start immediate.
    func warmUp() async
}

extension AudioTranscribing {
    public func warmUp() async {}
}

/// Tracks how far into the call the audio has reached, so a recognition result
/// can be stamped with when it was spoken rather than when it arrived.
final class AudioClock: @unchecked Sendable {
    private let lock = NSLock()
    private var seconds = 0.0

    var position: Duration {
        lock.lock(); defer { lock.unlock() }
        return .seconds(seconds)
    }

    func advance(frames: Int, rate: Double) {
        guard rate > 0 else { return }
        lock.lock(); seconds += Double(frames) / rate; lock.unlock()
    }
}
