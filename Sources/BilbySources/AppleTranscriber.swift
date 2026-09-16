// AVAudioPCMBuffer is not Sendable, so a stream of them cannot cross an
// isolation boundary under strict concurrency. Buffers here are produced and
// consumed by one task and never shared, which the compiler cannot see.
@preconcurrency import AVFoundation
import BilbyCore
import Foundation
import Speech

/// Apple's on-device speech model, exposed as a stream of `Utterance`.
///
/// Only volatile results are forwarded. Measured on real audio, finals arrive
/// up to 4.5 s later, carry no punctuation the volatile result did not already
/// have, and sometimes reword what is already on screen — one turned
/// "off site" into "of site". Waiting for them would cost the latency budget
/// and buy worse text.
public struct AppleTranscriber: Sendable {
    private let locale: Locale
    /// Called with each buffer's frame count. Lets the app tell "no audio
    /// arrived" apart from "audio arrived but nothing was recognised" — the
    /// two look identical on an empty caption bar.
    private let onAudio: (@Sendable (Int) -> Void)?

    public init(
        locale: Locale = Locale(identifier: "en_US"),
        onAudio: (@Sendable (Int) -> Void)? = nil
    ) {
        self.locale = locale
        self.onAudio = onAudio
    }

    /// Takes a factory rather than a stream: a stream of non-Sendable buffers
    /// cannot cross an isolation boundary, so it is created inside the task
    /// that consumes it and never escapes.
    public func utterances(
        from source: @escaping @Sendable () -> AsyncStream<AVAudioPCMBuffer>
    ) -> AsyncStream<Utterance> {
        AsyncStream { continuation in
            let task = Task {
                let transcriber = SpeechTranscriber(
                    locale: locale,
                    transcriptionOptions: [],
                    reportingOptions: [.volatileResults],
                    attributeOptions: [.audioTimeRange]
                )
                let analyzer = SpeechAnalyzer(modules: [transcriber])
                guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
                    compatibleWith: [transcriber]
                ) else {
                    Log.write("speech: FAILED — no compatible audio format for \(locale.identifier)")
                    continuation.finish()
                    return
                }
                Log.write("speech: analyzer format \(format.sampleRate) Hz, \(format.channelCount) ch")

                let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
                do { try await analyzer.start(inputSequence: input) }
                catch { Log.write("speech: FAILED to start — \(error)") }

                var heard = 0
                let reader = Task {
                    for try await result in transcriber.results where !result.isFinal {
                        var spokenAt = Duration.zero
                        for run in result.text.runs {
                            if let range = run.audioTimeRange {
                                spokenAt = .seconds(range.end.seconds)
                            }
                        }
                        let text = String(result.text.characters)
                        if heard == 0 { Log.write("speech: first result — \(text)") }
                        heard += 1
                        continuation.yield(Utterance(text, at: spokenAt))
                    }
                }

                var converter: AVAudioConverter?
                var fed = 0
                for await buffer in source() {
                    onAudio?(Int(buffer.frameLength))
                    guard let converted = convert(buffer, to: format, using: &converter) else {
                        Log.write("speech: conversion failed from \(buffer.format)")
                        continue
                    }
                    if fed == 0 { Log.write("speech: first buffer converted and fed") }
                    fed += 1
                    feed.yield(AnalyzerInput(buffer: converted))
                }
                feed.finish()
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
                _ = try? await reader.value
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func convert(
        _ buffer: AVAudioPCMBuffer,
        to format: AVAudioFormat,
        using converter: inout AVAudioConverter?
    ) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        if converter == nil { converter = AVAudioConverter(from: buffer.format, to: format) }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        guard let output = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        ) else { return nil }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return error == nil ? output : nil
    }
}
