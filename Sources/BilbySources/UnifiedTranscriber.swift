@preconcurrency import AVFoundation
import BilbyCore
import FluidAudio
import Foundation

/// Parakeet Unified 0.6B — the recogniser Bilby uses.
///
/// Chosen for one property: it emits punctuation and capitals while streaming.
/// That is not about how the text looks. Apple's translator is good on whole
/// sentences and bad on fragments — given "i knew that i could / do it again"
/// it produced «Сделай это снова», an imperative — and a full stop from the
/// model is the only trustworthy sentence boundary. Every substitute we tried
/// (word counts, pauses, end-of-utterance tokens) either fired at the wrong
/// place or hardly fired at all.
///
/// English only, which costs nothing here: the case is an English meeting read
/// in another language.
public struct UnifiedTranscriber: AudioTranscribing {

    private let onAudio: (@Sendable (Int) -> Void)?

    public init(onAudio: (@Sendable (Int) -> Void)? = nil) {
        self.onAudio = onAudio
    }

    /// Latency is geometry, not compute: (chunk + right) × 80 ms, baked into
    /// the CoreML export. NVIDIA ships four windows — 320 ms, 640 ms, 1.1 s and
    /// 2.1 s — and only the fastest is worth having: the slower ones buy a
    /// little accuracy with a delay people feel immediately.
    private var config: UnifiedConfig {
        UnifiedConfig(chunkFrames: 2, rightFrames: 2)
    }

    public func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness {
        let started = ContinuousClock.now
        Log.write("asr: warming up…")
        progress(.preparing)
        do {
            try await StreamingUnifiedAsrManager(config: config).loadModels(
                to: nil, configuration: nil,
                progressHandler: { update in
                    // Below 1 the files are still arriving. At 1 CoreML compiles
                    // for this machine, which reports nothing until it is done.
                    progress(update.fractionCompleted < 1 ? .downloading(update.fractionCompleted) : .preparing)
                })
            Log.write("asr: warm in \(ContinuousClock.now - started)")
            progress(.ready)
            return .ready
        } catch {
            Log.write("asr: FAILED to warm — \(error)")
            let failed = Readiness.failed(Self.explain(error))
            progress(failed)
            return failed
        }
    }

    /// One sentence a person can act on. The error itself goes to the log.
    static func explain(_ error: Error) -> String {
        let text = String(describing: error).lowercased()
        let offline = ["offline", "internet", "network", "hostname", "-1009", "-1001", "timed out"]
        if offline.contains(where: text.contains) {
            return "Speech recognition needs a one-time download. Connect to the internet and try again."
        }
        return "Speech recognition couldn’t be set up. Try again."
    }

    public func utterances(
        from source: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>
    ) -> AsyncStream<Utterance> {
        AsyncStream { continuation in
            let task = Task {
                let manager = StreamingUnifiedAsrManager(config: config)
                let clock = AudioClock()
                let spoken = RunningTranscript()

                do {
                    try await manager.loadModels()
                    Log.write("asr: ready")
                } catch {
                    Log.write("asr: FAILED to load — \(error)")
                    continuation.finish()
                    return
                }

                await manager.setPartialTranscriptCallback { text in
                    // No pause detection: this engine punctuates, and its full
                    // stops beat any timing guess.
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
