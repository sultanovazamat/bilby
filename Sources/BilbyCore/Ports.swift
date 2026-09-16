/// The edges of the app. Each has a real implementation backed by an Apple
/// framework and a fake used in tests, so the core never needs audio, a
/// network, or Apple Intelligence to be exercised.

/// Raw audio captured from another app.
public struct AudioFrame: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public init(samples: [Float], sampleRate: Double) {
        self.samples = samples
        self.sampleRate = sampleRate
    }
}

public protocol AudioSource: Sendable {
    func frames() -> AsyncStream<AudioFrame>
}

public protocol Transcribing: Sendable {
    func utterances(from: AsyncStream<AudioFrame>) -> AsyncStream<Utterance>
}

public protocol Translating: Sendable {
    func translate(_ text: String, to language: Language) async throws -> String
}

public protocol Explaining: Sendable {
    func explain(_ phrase: String, context: [Line]) async throws -> String
}
