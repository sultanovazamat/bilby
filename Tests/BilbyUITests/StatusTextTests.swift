import BilbyCore
import Testing

@testable import BilbyUI

@Suite("Status text")
struct StatusTextTests {
    @Test("waiting text names the phase in plain words")
    func waiting() {
        #expect(StatusText.waiting(readiness: .idle, app: "Zoom") == "Loading speech recognition…")
        #expect(StatusText.waiting(readiness: .preparing(nil), app: "Zoom") == "Loading speech recognition…")
        #expect(StatusText.waiting(readiness: .preparing(0.4), app: "Zoom") == "Loading speech recognition, 40%")
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
        #expect(
            StatusText.problem(.failed(.permission), app: "Zoom")
                == "Bilby isn’t allowed to hear other apps.")
        // Each of these used to read "Something went wrong. Start captions
        // again." — advice that cannot work for either of them.
        #expect(
            StatusText.problem(.failed(.noOutputDevice), app: "Zoom")
                == "This Mac has no sound output selected, so there is nothing to listen to.")
        #expect(
            StatusText.problem(.failed(.appGone), app: "Zoom")
                == "Zoom stopped playing audio. Start captions again when it does.")
        #expect(
            StatusText.problem(.failed(.plumbing("start device -66680")), app: "Zoom")
                == "Something went wrong. Start captions again.")
    }

    @Test("only a refused tap is offered as something the user can fix")
    func onlyPermissionIsFixable() {
        #expect(StatusText.isPermission(.failed(.permission)))
        #expect(!StatusText.isPermission(.failed(.appGone)))
        #expect(!StatusText.isPermission(.failed(.noOutputDevice)))
        #expect(!StatusText.isPermission(.failed(.plumbing("create aggregate -4"))))
        #expect(!StatusText.isPermission(.flowing(lines: 2)))
    }
}

/// Translation failing used to be completely invisible: `CaptionSession`
/// discards translation errors by design, so a missing language pair showed
/// as English-only captions forever while the menu reported a healthy
/// pipeline. These pin the state that makes it visible.
@Suite("Translation that never comes back")
struct NoTranslationTests {
    private func diagnostics(lines: Int, translations: Int) -> Diagnostics {
        let counter = Diagnostics()
        counter.audio(4096)
        counter.heardSomething()
        for _ in 0..<lines { counter.committedLine() }
        for _ in 0..<translations { counter.translated() }
        return counter
    }

    @Test("one or two untranslated sentences are just a pair being slow")
    func patientAtFirst() {
        #expect(diagnostics(lines: 1, translations: 0).state == .flowing(lines: 1))
        #expect(diagnostics(lines: 2, translations: 0).state == .flowing(lines: 2))
    }

    @Test("three sentences with nothing translated is a failure, and it is named")
    func namedAfterThree() {
        let state = diagnostics(lines: 3, translations: 0).state
        #expect(state == .noTranslation(lines: 3))
        #expect(
            StatusText.problem(state, app: "Zoom")
                == "Nothing is coming back translated. The language may need downloading again.")
    }

    @Test("a pipeline that does translate stays quiet")
    func quietWhenWorking() {
        let state = diagnostics(lines: 5, translations: 4).state
        #expect(state == .flowing(lines: 5))
        #expect(StatusText.problem(state, app: "Zoom") == nil)
    }

    @Test("translations recovering clears the warning")
    func recovers() {
        let counter = diagnostics(lines: 3, translations: 0)
        #expect(counter.state == .noTranslation(lines: 3))
        counter.translated()
        #expect(counter.state == .flowing(lines: 3))
    }
}
