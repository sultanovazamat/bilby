import BilbyCore

/// Translates by tagging the source, so assertions read plainly.
struct EchoTranslator: Translating {
    var failOn: Set<String> = []
    struct Failed: Error {}

    func translate(_ text: String, to language: Language) async throws -> String {
        if failOn.contains(text) { throw Failed() }
        return "[\(language.code)] \(text)"
    }
}

func stream(_ utterances: [Utterance]) -> AsyncStream<Utterance> {
    AsyncStream { continuation in
        for utterance in utterances { continuation.yield(utterance) }
        continuation.finish()
    }
}
