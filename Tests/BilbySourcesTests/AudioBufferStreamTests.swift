@preconcurrency import AVFoundation
import BilbyCore
import Synchronization
import Testing

@testable import BilbySources

@Suite("Audio buffer stream")
struct AudioBufferStreamTests {
    @Test("audio overload preserves the queued prefix, reports failure once and closes")
    func overloadStopsInsteadOfSkippingAudio() async throws {
        let failures = Mutex<[TapFailure]>([])
        let output = SystemAudioTap.bufferStream { failure in failures.withLock { $0.append(failure) } }
        let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        for index in 0..<110 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1))
            buffer.frameLength = 1
            buffer.floatChannelData?[0][0] = Float(index)
            output.yield(buffer)
        }
        #expect(failures.withLock { $0 } == [.overloaded])
        var samples: [Float] = []
        for await buffer in output.stream {
            samples.append(try #require(buffer.floatChannelData?[0][0]))
        }
        #expect(samples == (0..<100).map(Float.init))
    }
}
