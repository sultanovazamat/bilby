import Testing

@testable import BilbySources

@Suite("Explaining a failed download")
struct ExplainTests {
    struct Offline: Error, CustomStringConvertible {
        var description: String { "URLSessionTask failed: The Internet connection appears to be offline. (-1009)" }
    }
    struct Broken: Error, CustomStringConvertible {
        var description: String { "modelLoadFailed(encoder.mlmodelc)" }
    }

    @Test("a network failure asks for a connection; anything else asks to try again")
    func sentences() {
        #expect(
            UnifiedTranscriber.explain(Offline())
                == "Speech recognition needs a model download. Connect to the internet and try again.")
        #expect(UnifiedTranscriber.explain(Broken()) == "Speech recognition couldn’t be set up. Try again.")
        #expect(
            UnifiedTranscriber.explain(SpeechModelError.download)
                == "Speech recognition needs a model download. Connect to the internet and try again.")
    }
}
