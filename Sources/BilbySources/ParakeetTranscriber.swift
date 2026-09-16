// The tap owns each buffer and hands it over; nothing else holds a reference,
// which strict concurrency cannot see for a non-Sendable AVFoundation type.
@preconcurrency import AVFoundation
import BilbyCore
import FluidAudio
import Foundation

/// NVIDIA Parakeet EOU, streaming, on the Neural Engine.
///
/// Chosen after measurement, not preference. Apple's recogniser delivers its
/// results in bursts every 3.6 s — five to nine sentences inside 200 ms, then
/// a still screen — and no interface can make that readable. This one runs on
/// 160 ms chunks and reports the end of an utterance itself, so a caption
/// boundary is the model's own decision instead of my guess at punctuation.
public struct ParakeetTranscriber: AudioTranscribing {
    private let onAudio: (@Sendable (Int) -> Void)?

    public init(onAudio: (@Sendable (Int) -> Void)? = nil) {
        self.onAudio = onAudio
    }

    public func utterances(
        from source: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>
    ) -> AsyncStream<Utterance> {
        AsyncStream { continuation in
            let task = Task {
                let manager = StreamingEouAsrManager(chunkSize: .ms160)
                let clock = AudioClock()

                do {
                    Log.write("parakeet: loading models (first run downloads them)…")
                    let started = ContinuousClock.now
                    try await manager.loadModels()
                    Log.write("parakeet: ready in \(ContinuousClock.now - started)")
                } catch {
                    Log.write("parakeet: FAILED to load — \(error)")
                    continuation.finish()
                    return
                }

                // Parakeet reports the whole session transcript every time, so
                // the adapter subtracts what has already been closed. Without
                // this the core sees an ever-growing utterance and ends up
                // retranslating the entire monologue several times a second.
                let spoken = Transcript()

                await manager.setPartialCallback { text in
                    let tail = spoken.tail(of: text)
                    guard !tail.isEmpty else { return }
                    continuation.yield(Utterance(tail, isFinal: false, at: clock.position))
                }
                await manager.setEouCallback { text in
                    let tail = spoken.close(text)
                    guard !tail.isEmpty else { return }
                    continuation.yield(Utterance(tail, isFinal: true, at: clock.position))
                }

                for await buffer in source() {
                    onAudio?(Int(buffer.frameLength))
                    clock.advance(frames: Int(buffer.frameLength), rate: buffer.format.sampleRate)
                    // The manager resamples to 16 kHz mono itself.
                    _ = try? await manager.process(audioBuffer: buffer)
                }
                _ = try? await manager.finish()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}


/// Remembers how much of Parakeet's cumulative transcript is already closed.
private final class Transcript: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = ""

    /// What has been said since the last end of utterance.
    func tail(of whole: String) -> String {
        lock.lock(); defer { lock.unlock() }
        return String(whole.dropFirst(min(closed.count, whole.count)))
            .trimmingCharacters(in: .whitespaces)
    }

    /// Closes the current utterance and returns it.
    func close(_ whole: String) -> String {
        lock.lock(); defer { lock.unlock() }
        let tail = String(whole.dropFirst(min(closed.count, whole.count)))
            .trimmingCharacters(in: .whitespaces)
        closed = whole
        return tail
    }
}
