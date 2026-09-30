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
    private static let chunkFrames = 2
    private static let rightFrames = 2
    private static var config: UnifiedConfig {
        UnifiedConfig(chunkFrames: chunkFrames, rightFrames: rightFrames)
    }
    /// How far past a word the recogniser has to hear before it reports it.
    private static let lookahead = Double(chunkFrames + rightFrames) * 0.08

    /// Loaded once and kept until the app quits. A warm-up whose model was let
    /// go bought nothing: the session loaded it again — 15 s from cold — and
    /// the audio tap, which is what asks macOS for permission, waited behind
    /// it.
    private static let resident = ResidentModel<StreamingUnifiedAsrManager> {
        let manager = StreamingUnifiedAsrManager(config: config)
        try await manager.loadModels()
        return manager
    }

    /// Shorter than this is rarely a thought, and "yeah" on a line of its
    /// own reads as noise. A stop does not end a sentence on fewer words:
    /// they wait for the rest of it.
    private static let fewestWords = 3

    public func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness {
        let started = ContinuousClock.now
        Log.write("asr: warming up…")
        progress(.preparing(nil))
        do {
            try await Self.resident.warm(loading: {
                let manager = StreamingUnifiedAsrManager(config: Self.config)
                try await manager.loadModels(
                    to: nil, configuration: nil,
                    progressHandler: { update in
                        // Below 1 the files are still arriving. At 1 CoreML
                        // compiles for this machine, which reports nothing
                        // until it is done.
                        progress(update.fractionCompleted < 1 ? .downloading(update.fractionCompleted) : .preparing(nil))
                    })
                return manager
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
                let clock = AudioClock()
                let spoken = RunningTranscript()
                let pulse = Pulse()

                // No pause detection: this engine punctuates, and its full
                // stops beat any timing guess.
                @Sendable func partial(_ text: String) {
                    pulse.heard()
                    let seen = spoken.observe(text, pause: nil)
                    guard !seen.tail.isEmpty else { return }
                    continuation.yield(Utterance(seen.tail, isFinal: false, at: clock.position))
                }

                // Seconds of silence fed before the real stream, which the
                // recogniser counts in its own word times and our clock
                // does not.
                var primed: TimeInterval = 0

                func prepared(fresh: Bool) async -> StreamingUnifiedAsrManager? {
                    primed = 0
                    let manager: StreamingUnifiedAsrManager
                    do {
                        // Already loaded, unless this is a restart or the app
                        // was asked to listen before anything warmed it.
                        manager = fresh ? try await Self.resident.replace() : try await Self.resident.borrow()
                        // A lent model still holds the last session's words.
                        try await manager.reset()
                    } catch {
                        Log.write("asr: FAILED to load — \(error)")
                        return nil
                    }
                    // The first inference sets the graph up on the Neural
                    // Engine while the tap is already delivering, and an
                    // unbounded queue never drains. Paying it here, before
                    // any audio is being consumed, costs the same once.
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
                        // Measured before the buffer is handed over: reading
                        // it afterwards is a read of something another
                        // isolation domain now owns.
                        let seconds = Double(silence.frameLength) / format.sampleRate
                        do {
                            try await manager.appendAudio(silence)
                            try await manager.processBufferedAudio()
                            primed = seconds
                            Log.write("asr: primed in \(ContinuousClock.now - begun)")
                        } catch {
                            Log.write("asr: priming FAILED — \(error)")
                        }
                    }
                    // Set after priming, so a second of silence cannot be
                    // mistaken for something somebody said.
                    await manager.setPartialTranscriptCallback(partial)
                    return manager
                }

                guard var manager = await prepared(fresh: false) else {
                    continuation.finish()
                    return
                }
                Log.write("asr: ready")

                // Swallowing these is how a recogniser that had stopped
                // working came to look exactly like a room that had gone
                // quiet: audio still arriving, nothing on screen, and a log
                // full of frame counts saying everything was fine.
                var failures = 0
                var toldAt = ContinuousClock.now - .seconds(60)
                var checkedAt = ContinuousClock.now
                var restartedAt = ContinuousClock.now - .seconds(60)
                // Where this recogniser's clock sits against the session's.
                var managerZero = clock.elapsed
                var lastWordEnd: TimeInterval = 0
                var sinceTimings = 0
                // For speech the model leaves unpunctuated: its own full stops
                // end sentences, and this only ends one it never will.
                var backstop = SentenceBackstop(lookahead: Self.lookahead)

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

                    // Roughly every fifty milliseconds.
                    sinceTimings += 1
                    if sinceTimings >= 5 {
                        sinceTimings = 0
                        for timing in await manager.consumeWordTimings() {
                            lastWordEnd = max(lastWordEnd, timing.endTime)
                        }
                        let heardSoFar = clock.elapsed - managerZero + primed
                        if backstop.ends(heard: heardSoFar, lastWordEnd: lastWordEnd),
                            let finished = spoken.close(fewest: Self.fewestWords)
                        {
                            continuation.yield(Utterance(finished, isFinal: true, at: clock.position))
                        }
                    }

                    guard ContinuousClock.now - checkedAt >= .seconds(2) else { continue }
                    checkedAt = ContinuousClock.now
                    if let line = pulse.report(stage: "asr") { Log.write(line) }

                    // Words stopping while the sound did not is the one
                    // failure the user cannot act on and cannot see the cause
                    // of: the bar simply freezes. Rather than leave it, start
                    // the recogniser again. The models are cached, so this
                    // costs a moment, and the rate limit keeps a recogniser
                    // that cannot recover from thrashing.
                    guard pulse.isStalled(after: .seconds(8)),
                        ContinuousClock.now - restartedAt >= .seconds(30)
                    else { continue }
                    restartedAt = ContinuousClock.now
                    Log.write("asr: restarting — words stopped while the audio did not")
                    guard let fresh = await prepared(fresh: true) else {
                        Log.write("asr: restart FAILED, carrying on with the old one")
                        continue
                    }
                    manager = fresh
                    spoken.reset()
                    pulse.reset()
                    managerZero = clock.elapsed
                    lastWordEnd = 0
                    // The new recogniser's clock starts again from nothing.
                    backstop = SentenceBackstop(lookahead: Self.lookahead)
                    Log.write("asr: restarted")
                }
                _ = try? await manager.finish()
                // Kept for the next session, which then starts at once.
                await Self.resident.giveBack(manager)
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
