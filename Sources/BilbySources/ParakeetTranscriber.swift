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
    /// A gap this long in the arriving words means the speaker finished a
    /// thought. Shorter and we cut inside phrases; longer and captions lag.
    private let pause: Duration

    public init(
        pause: Duration = .milliseconds(450),
        onAudio: (@Sendable (Int) -> Void)? = nil
    ) {
        self.pause = pause
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
                let pause = self.pause

                await manager.setPartialCallback { text in
                    // Where the speaker stopped is where the thought ended.
                    // Cutting on a word count instead put "wasn't" at the end of
                    // one line and "really that risky" at the start of the next,
                    // so the screen asserted the opposite of what was said.
                    let seen = spoken.observe(text, pause: pause)
                    if let finished = seen.finished {
                        continuation.yield(Utterance(finished, isFinal: true, at: clock.position))
                    }
                    guard !seen.tail.isEmpty else { return }
                    continuation.yield(Utterance(seen.tail, isFinal: false, at: clock.position))
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


/// Remembers how much of Parakeet's cumulative transcript is already closed,
/// and notices when the speaker stopped.
private final class Transcript: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = ""
    private var latest = ""
    private var changedAt = ContinuousClock.now

    /// Takes the model's running transcript and reports what is new, plus the
    /// thought that a pause has just ended, if any.
    func observe(_ whole: String, pause: Duration) -> (finished: String?, tail: String) {
        lock.lock(); defer { lock.unlock() }

        var finished: String?
        if whole != latest {
            let previous = String(latest.dropFirst(min(closed.count, latest.count)))
                .trimmingCharacters(in: .whitespaces)
            // Four words: shorter fragments are rarely a whole thought, and a
            // stray "yeah" on its own line reads as noise.
            if ContinuousClock.now - changedAt >= pause,
               previous.split(whereSeparator: \.isWhitespace).count >= 4 {
                finished = previous
                closed = latest
            }
            latest = whole
            changedAt = ContinuousClock.now
        }

        let tail = String(whole.dropFirst(min(closed.count, whole.count)))
            .trimmingCharacters(in: .whitespaces)
        return (finished, tail)
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
