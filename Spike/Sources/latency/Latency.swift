import AVFoundation
import Foundation
import Speech

/// Measures the only number that decides whether Bilby is a caption bar or a
/// transcript viewer: how long after a word is spoken does its text appear.
///
/// Audio is fed at wall-clock pace, exactly as a live tap would, so lag is
/// (time the result arrived) − (time the word was actually spoken).
@main
struct Latency {
    static func main() async throws {
        let file = try AVAudioFile(forReading: URL(filePath: "/tmp/meeting.aiff"))

        let transcriber = SpeechTranscriber(
            locale: Locale(identifier: "en_US"),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            print("no compatible audio format"); return
        }
        print("feeding \(format.sampleRate) Hz, \(format.channelCount) ch")

        let (input, feed) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: input)

        let started = ContinuousClock.now
        let reader = Task {
            var firstLag: Duration?
            var lags: [Double] = []
            for try await result in transcriber.results {
                let elapsed = ContinuousClock.now - started
                var spokenAt: Double?
                for run in result.text.runs {
                    if let range = run.audioTimeRange { spokenAt = range.end.seconds }
                }
                let text = String(result.text.characters)
                guard let spokenAt else {
                    print("  [\(result.isFinal ? "final" : "live")] \(text)")
                    continue
                }
                let lag = elapsed.seconds - spokenAt
                lags.append(lag)
                if firstLag == nil { firstLag = elapsed }
                print(String(format: "  %@ lag %.2fs — %@",
                             result.isFinal ? "[final]" : "[live] ", lag, text))
            }
            return lags
        }

        // Feed 100 ms of audio every 100 ms.
        let converter = AVAudioConverter(from: file.processingFormat, to: format)!
        let chunk = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        while file.framePosition < file.length {
            guard let source = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: chunk
            ) else { break }
            try file.read(into: source, frameCount: chunk)
            if source.frameLength == 0 { break }

            let ratio = format.sampleRate / file.processingFormat.sampleRate
            guard let target = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
            ) else { break }
            var done = false
            var error: NSError?
            converter.convert(to: target, error: &error) { _, status in
                if done { status.pointee = .noDataNow; return nil }
                done = true
                status.pointee = .haveData
                return source
            }
            if let error { print("convert failed: \(error)"); break }
            feed.yield(AnalyzerInput(buffer: target))
            try await Task.sleep(for: .milliseconds(100))
        }
        feed.finish()
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let lags = try await reader.value
        if lags.isEmpty { print("\nno timed results"); return }
        let sorted = lags.sorted()
        print(String(format: "\nresults %d · median %.2fs · p90 %.2fs · max %.2fs",
                     lags.count, sorted[sorted.count / 2],
                     sorted[Int(Double(sorted.count) * 0.9)], sorted.last!))
    }
}

extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}
