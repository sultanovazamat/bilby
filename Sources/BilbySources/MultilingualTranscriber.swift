import Accelerate
@preconcurrency import AVFoundation
import BilbyCore
import FluidAudio
import Foundation

/// Nemotron 3.5 streaming multilingual — the second recogniser, kept so the
/// choice between them can be settled on a real meeting.
///
/// It differs from the English one in three ways that matter here. It detects
/// the language rather than being told, covering forty language locales. It
/// punctuates natively, which is the only boundary this engine offers: unlike
/// Parakeet Unified it publishes no word timings while streaming, so there is
/// no pause to fall back on and the clause buffer's word count is the last
/// resort. And its punctuation is documented to thin out on long sessions at
/// small chunk sizes, so it runs at the tier the library recommends when
/// punctuation matters rather than the fastest one.
public struct MultilingualTranscriber: AudioTranscribing {
    /// 1120 ms is the smallest tier FluidAudio recommends when punctuation
    /// matters; below it, punctuation is documented to become sparse over a
    /// long session, and punctuation is the only thing cutting sentences here.
    private static let chunkMs = 1120

    private let onAudio: (@Sendable (Int) -> Void)?

    public init(onAudio: (@Sendable (Int) -> Void)? = nil) {
        self.onAudio = onAudio
    }

    public func warmUp(progress: @escaping @Sendable (Readiness) -> Void) async -> Readiness {
        let started = ContinuousClock.now
        Log.write("asr: warming up the multilingual model…")
        progress(.preparing)
        do {
            _ = try await MultilingualModels.shared.loaded { update in
                progress(update.fractionCompleted < 1 ? .downloading(update.fractionCompleted) : .preparing)
            }
            Log.write("asr: multilingual warm in \(ContinuousClock.now - started)")
            progress(.ready)
            return .ready
        } catch {
            Log.write("asr: multilingual FAILED to warm — \(error)")
            let failed = Readiness.failed(UnifiedTranscriber.explain(error))
            progress(failed)
            return failed
        }
    }

    public func utterances(
        from source: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>
    ) -> AsyncStream<Utterance> {
        AsyncStream { continuation in
            let task = Task {
                let clock = AudioClock()
                let spoken = RunningTranscript()
                let pulse = Pulse()

                @Sendable func partial(_ text: String) {
                    pulse.heard()
                    let seen = spoken.observe(text, pause: nil)
                    guard !seen.tail.isEmpty else { return }
                    continuation.yield(Utterance(seen.tail, isFinal: false, at: clock.position))
                }

                func prepared() async -> StreamingNemotronMultilingualAsrManager? {
                    do {
                        let shared = try await MultilingualModels.shared.loaded { _ in }
                        let manager = StreamingNemotronMultilingualAsrManager()
                        try await manager.loadFromShared(shared)
                        // Told nothing, so it reports what it hears.
                        await manager.setLanguage("auto")
                        await manager.setPartialCallback(partial)
                        return manager
                    } catch {
                        Log.write("asr: multilingual FAILED to load — \(error)")
                        return nil
                    }
                }

                guard var manager = await prepared() else {
                    continuation.finish()
                    return
                }
                Log.write("asr: multilingual ready")

                var failures = 0
                var toldAt = ContinuousClock.now - .seconds(60)
                var checkedAt = ContinuousClock.now
                var restartedAt = ContinuousClock.now - .seconds(60)
                var reportedLanguage: String?

                for await buffer in source() {
                    onAudio?(Int(buffer.frameLength))
                    pulse.sawAudio(peak: buffer.peak)
                    clock.advance(frames: Int(buffer.frameLength), rate: buffer.format.sampleRate)
                    do {
                        _ = try await manager.process(audioBuffer: buffer)
                    } catch {
                        failures += 1
                        if ContinuousClock.now - toldAt >= .seconds(5) {
                            toldAt = ContinuousClock.now
                            Log.write("asr: multilingual FAILED on audio, \(failures) so far — \(error)")
                        }
                    }

                    guard ContinuousClock.now - checkedAt >= .seconds(2) else { continue }
                    checkedAt = ContinuousClock.now
                    if let line = pulse.report(stage: "asr") { Log.write(line) }
                    if let heard = await manager.detectedLanguage(), heard != reportedLanguage {
                        reportedLanguage = heard
                        Log.write("asr: hearing \(heard)")
                    }

                    guard pulse.isStalled(after: .seconds(8)),
                        ContinuousClock.now - restartedAt >= .seconds(30)
                    else { continue }
                    restartedAt = ContinuousClock.now
                    Log.write("asr: restarting the multilingual model — words stopped, audio did not")
                    guard let fresh = await prepared() else {
                        Log.write("asr: restart FAILED, carrying on with the old one")
                        continue
                    }
                    manager = fresh
                    spoken.reset()
                    pulse.reset()
                    Log.write("asr: restarted")
                }
                _ = try? await manager.finish()
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Loads the multilingual model once and hands the same weights to every
/// session, the way its own API intends.
actor MultilingualModels {
    static let shared = MultilingualModels()

    private var models: SharedNemotronMultilingualModels?

    func loaded(progress: @escaping ProgressHandler) async throws -> SharedNemotronMultilingualModels {
        if let models { return models }
        let chunk = MultilingualTranscriber.chunkMsForSharing

        func fetch() async throws -> URL {
            try await StreamingNemotronMultilingualAsrManager.downloadVariant(
                languageCode: "auto", chunkMs: chunk, progressHandler: progress)
        }

        let directory = try await fetch()
        do {
            let fresh = try await StreamingNemotronMultilingualAsrManager.preloadShared(from: directory)
            models = fresh
            return fresh
        } catch {
            // A download that is interrupted leaves the big weights as
            // `.partial`, and the library calls a variant cached when its
            // metadata file exists and nothing else. Since that file lands
            // in the first second, one quit during the download makes the
            // model permanently unloadable and nothing ever fetches it
            // again. Removing the marker sends it back down the download
            // path, where the half-written file is resumed rather than
            // thrown away.
            Log.write("asr: multilingual model is incomplete, fetching the rest — \(error)")
            try? FileManager.default.removeItem(at: directory.appendingPathComponent("metadata.json"))
            let repaired = try await fetch()
            do {
                let fresh = try await StreamingNemotronMultilingualAsrManager.preloadShared(from: repaired)
                models = fresh
                return fresh
            } catch {
                // Still broken: throw the variant away so the next attempt
                // starts from nothing rather than from this.
                Log.write("asr: multilingual model could not be repaired, discarding it — \(error)")
                try? FileManager.default.removeItem(at: repaired)
                throw error
            }
        }
    }
}

extension MultilingualTranscriber {
    /// Exposed so the loader and the transcriber cannot disagree about it.
    static var chunkMsForSharing: Int { chunkMs }
}
