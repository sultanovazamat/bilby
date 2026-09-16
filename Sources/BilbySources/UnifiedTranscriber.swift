@preconcurrency import AVFoundation
import BilbyCore
import FluidAudio
import Foundation

/// Parakeet Unified 0.6B: streaming, and the only engine we have that emits
/// punctuation and capitals.
///
/// That matters less for how the text looks than for where it can be cut.
/// Apple's translator works on whole sentences; fed a fragment it produced
/// "Сделай это снова" — an imperative — from "i knew that i could do it again".
/// A full stop from the model is a real sentence boundary, which no amount of
/// timing or word counting can infer.
///
/// The price is latency — about a second against EOU's 160 ms — and English
/// only. Both are acceptable for the settled line; neither is for the live one.
public struct UnifiedTranscriber: AudioTranscribing {
    private let onAudio: (@Sendable (Int) -> Void)?

    public init(onAudio: (@Sendable (Int) -> Void)? = nil) {
        self.onAudio = onAudio
    }

    public func warmUp() async {
        let started = ContinuousClock.now
        Log.write("unified: warming up…")
        do {
            try await StreamingUnifiedAsrManager().loadModels()
            Log.write("unified: warm in \(ContinuousClock.now - started)")
        } catch {
            Log.write("unified: FAILED to warm — \(error)")
        }
    }

    public func utterances(
        from source: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>
    ) -> AsyncStream<Utterance> {
        AsyncStream { continuation in
            let task = Task {
                let manager = StreamingUnifiedAsrManager()
                let clock = AudioClock()
                let spoken = RunningTranscript()

                do {
                    Log.write("unified: loading models…")
                    let started = ContinuousClock.now
                    try await manager.loadModels()
                    Log.write("unified: ready in \(ContinuousClock.now - started)")
                } catch {
                    Log.write("unified: FAILED to load — \(error)")
                    continuation.finish()
                    return
                }

                await manager.setPartialTranscriptCallback { text in
                    // No pause detection: this engine punctuates, and its full
                    // stops are better boundaries than any timing guess.
                    let seen = spoken.observe(text, pause: nil)
                    guard !seen.tail.isEmpty else { return }
                    continuation.yield(Utterance(seen.tail, isFinal: false, at: clock.position))
                }

                for await buffer in source() {
                    onAudio?(Int(buffer.frameLength))
                    clock.advance(frames: Int(buffer.frameLength), rate: buffer.format.sampleRate)
                    try? await manager.appendAudio(buffer)
                    try? await manager.processBufferedAudio()
                }
                _ = try? await manager.finish()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
