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
