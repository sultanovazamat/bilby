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

    /// How far ahead the model listens before committing a word.
    ///
    /// Latency is geometry, not compute: (chunk + right) × 80 ms. Quantisation
    /// cannot change it; only a different export can, and NVIDIA ships four.
    public enum Latency: String, CaseIterable, Sendable {
        case ms320, ms640, ms1120, ms2080

        var frames: (chunk: Int, right: Int) {
            switch self {
            case .ms320: (2, 2)
            case .ms640: (7, 1)
            case .ms1120: (7, 7)
            case .ms2080: (13, 13)
            }
        }

        public var name: String {
            switch self {
            case .ms320: "320 ms — fastest"
            case .ms640: "640 ms"
            case .ms1120: "1.1 s"
            case .ms2080: "2.1 s — best accuracy"
            }
        }
    }

    private let latency: Latency
    private let onAudio: (@Sendable (Int) -> Void)?

    public init(latency: Latency = .ms320, onAudio: (@Sendable (Int) -> Void)? = nil) {
        self.latency = latency
        self.onAudio = onAudio
    }

    private var config: UnifiedConfig {
        UnifiedConfig(chunkFrames: latency.frames.chunk, rightFrames: latency.frames.right)
    }

    public func warmUp() async {
        let started = ContinuousClock.now
        Log.write("asr: warming up \(latency.rawValue)…")
        do {
            try await StreamingUnifiedAsrManager(config: config).loadModels()
            Log.write("asr: warm in \(ContinuousClock.now - started)")
        } catch {
            Log.write("asr: FAILED to warm — \(error)")
        }
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
                    Log.write("asr: \(latency.rawValue) ready")
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
