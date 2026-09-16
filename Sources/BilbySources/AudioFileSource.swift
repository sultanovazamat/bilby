import AVFoundation
import Foundation

/// Plays a file at wall-clock pace so the pipeline behaves exactly as it will
/// with a live tap. Used to exercise everything downstream before system audio
/// capture exists.
public struct AudioFileSource: Sendable {
    private let url: URL
    private let chunk: Duration

    public init(url: URL, chunk: Duration = .milliseconds(100)) {
        self.url = url
        self.chunk = chunk
    }

    public func buffers() -> AsyncStream<AVAudioPCMBuffer> {
        AsyncStream { continuation in
            let task = Task {
                guard let file = try? AVAudioFile(forReading: url) else {
                    continuation.finish()
                    return
                }
                let format = file.processingFormat
                let frames = AVAudioFrameCount(
                    format.sampleRate * Double(chunk.components.attoseconds) / 1e18
                    + format.sampleRate * Double(chunk.components.seconds)
                )
                while file.framePosition < file.length, !Task.isCancelled {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
                          (try? file.read(into: buffer, frameCount: frames)) != nil,
                          buffer.frameLength > 0
                    else { break }
                    continuation.yield(buffer)
                    try? await Task.sleep(for: chunk)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
