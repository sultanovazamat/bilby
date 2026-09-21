import AVFoundation
import Accelerate
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

    /// Loads the models before anyone asks for captions, reporting how far
    /// along it is, and returns the final state.
    ///
    /// Unified takes 50 s on a cold start and 580 MB on a fresh machine.
    /// Doing that silently inside the listening task meant the bar stayed
    /// invisible and the menu said "no audio" while the model downloaded.
    /// CoreML caches the compiled result, so warming up once makes the real
    /// start immediate.
    func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness
}

extension AudioTranscribing {
    public func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness { .ready }
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

    /// The same figure the recogniser times its words against.
    var elapsed: TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return seconds
    }

    func advance(frames: Int, rate: Double) {
        guard rate > 0 else { return }
        lock.lock(); seconds += Double(frames) / rate; lock.unlock()
    }
}

extension AVAudioPCMBuffer {
    /// The loudest sample in the buffer, 0…1.
    ///
    /// A tap delivers frames at the same rate whether the meeting is talking
    /// or paused, so a frame count says nothing about whether there was
    /// anything to hear. This is what separates a quiet room from a
    /// recogniser that has stopped working.
    var peak: Float {
        guard let data = floatChannelData else { return 0 }
        var loudest: Float = 0
        vDSP_maxmgv(data[0], 1, &loudest, vDSP_Length(Int(frameLength) * Int(format.channelCount)))
        return loudest
    }
}
