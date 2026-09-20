import BilbyCore
import Testing

@testable import BilbyUI

@Suite("Status text")
struct StatusTextTests {
    @Test("waiting text names the phase in plain words")
    func waiting() {
        #expect(StatusText.waiting(readiness: .idle, app: "Zoom") == "Getting ready…")
        #expect(StatusText.waiting(readiness: .preparing, app: "Zoom") == "Getting ready…")
        #expect(StatusText.waiting(readiness: .downloading(0.427), app: "Zoom") == "Downloading speech recognition, 43%")
        #expect(StatusText.waiting(readiness: .ready, app: "Zoom") == "Listening to Zoom…")
        #expect(StatusText.waiting(readiness: .ready, app: nil) == "Listening…")
        #expect(StatusText.waiting(readiness: .failed("No network."), app: "Zoom") == "No network.")
    }

    @Test("pipeline states become one sentence, or nothing when all is well")
    func problems() {
        #expect(StatusText.problem(.flowing(lines: 3), app: "Zoom") == nil)
        #expect(StatusText.problem(.noAudio, app: "Zoom") == "No sound from Zoom yet. Is it muted?")
        #expect(StatusText.problem(.noSpeech(frames: 48_000), app: "Zoom") == "Listening, no speech heard yet")
        #expect(StatusText.problem(.noSentence(utterances: 2), app: "Zoom") == "Listening…")
        #expect(StatusText.problem(.failed("create tap -4 'what'"), app: "Zoom") == "Bilby isn’t allowed to hear other apps.")
        #expect(StatusText.problem(.failed("no default output device"), app: "Zoom") == "Something went wrong. Start captions again.")
    }
}
