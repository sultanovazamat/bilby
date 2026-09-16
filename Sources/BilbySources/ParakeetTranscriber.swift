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

                // Partials are the live line; EOU closes the caption. This is
                // what replaces ClauseBuffer's punctuation guessing.
                await manager.setPartialCallback { text in
                    guard !text.isEmpty else { return }
                    continuation.yield(Utterance(text, isFinal: false, at: clock.position))
                }
                await manager.setEouCallback { text in
                    guard !text.isEmpty else { return }
                    continuation.yield(Utterance(text, isFinal: true, at: clock.position))
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
