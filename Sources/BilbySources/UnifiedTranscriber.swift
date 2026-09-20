import Accelerate
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
                let pulse = Pulse()

                do {
                    try await manager.loadModels()
                    Log.write("asr: ready")
                } catch {
                    Log.write("asr: FAILED to load — \(error)")
                    continuation.finish()
                    return
                }

                // The first inference pays for setting the graph up on the
                // Neural Engine, and the tap does not wait: every buffer that
                // arrives meanwhile queues, and an unbounded queue never
                // drains, so the captions run that far behind for the rest of
                // the session — measured at 10.8 s on a live call. Paying it
                // here, before the tap opens, costs the same seconds once and
                // the user is told what is happening.
                if let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2),
                    let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48000)
                {
                    silence.frameLength = silence.frameCapacity
                    if let data = silence.floatChannelData {
                        for channel in 0..<Int(format.channelCount) {
                            memset(data[channel], 0, Int(silence.frameLength) * MemoryLayout<Float>.size)
                        }
                    }
                    let begun = ContinuousClock.now
                    do {
                        try await manager.appendAudio(silence)
                        try await manager.processBufferedAudio()
                        Log.write("asr: primed in \(ContinuousClock.now - begun)")
                    } catch {
                        Log.write("asr: priming FAILED — \(error)")
                    }
                }

                // Set after priming, so a second of silence cannot be
                // mistaken for something somebody said.
                await manager.setPartialTranscriptCallback { text in
                    // No pause detection: this engine punctuates, and its full
                    // stops beat any timing guess.
                    pulse.heard()
                    let seen = spoken.observe(text, pause: nil)
                    guard !seen.tail.isEmpty else { return }
                    continuation.yield(Utterance(seen.tail, isFinal: false, at: clock.position))
                }

                // Swallowing these is how a recogniser that had stopped
                // working came to look exactly like a room that had gone
                // quiet: audio still arriving, nothing on screen, and a log
                // full of frame counts saying everything was fine.
                var failures = 0
                var toldAt = ContinuousClock.now - .seconds(60)
                var checkedAt = ContinuousClock.now

                for await buffer in source() {
                    onAudio?(Int(buffer.frameLength))
                    pulse.sawAudio(peak: buffer.peak)
                    clock.advance(frames: Int(buffer.frameLength), rate: buffer.format.sampleRate)
                    do {
                        try await manager.appendAudio(buffer)
                        try await manager.processBufferedAudio()
                    } catch {
                        failures += 1
                        if ContinuousClock.now - toldAt >= .seconds(5) {
                            toldAt = ContinuousClock.now
                            Log.write("asr: FAILED on audio, \(failures) so far — \(error)")
                        }
                    }
                    if ContinuousClock.now - checkedAt >= .seconds(2) {
                        checkedAt = ContinuousClock.now
                        if let line = pulse.report(stage: "asr") { Log.write(line) }
                    }
                }
                _ = try? await manager.finish()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
