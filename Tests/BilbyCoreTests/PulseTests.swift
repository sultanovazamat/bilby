import Testing

@testable import BilbyCore

@Suite("Pulse")
struct PulseTests {
    @Test("a pipeline that has done nothing yet is not a stalled one")
    func idleIsNotStalled() {
        let pulse = Pulse()
        #expect(pulse.report(stage: "captions", after: .zero) == nil)
    }

    @Test("a translation that has not come back is sized, once, and its return is too")
    func outstandingTranslation() throws {
        let pulse = Pulse()
        pulse.heard()
        pulse.translating(chars: 21)
        let first = try #require(pulse.report(stage: "captions", after: .zero))
        #expect(first.contains("captions: STALLED"))
        // Its length, not its words: the log must not carry the meeting.
        #expect(first.contains("21-character"))
        // Said once: a line every two seconds would bury the rest of the log.
        #expect(pulse.report(stage: "captions", after: .zero) == nil)

        // Back within the limit, the stall is declared over — once.
        pulse.translated()
        let recovered = try #require(pulse.report(stage: "captions", after: .seconds(60)))
        #expect(recovered.contains("recovered"))
        #expect(pulse.report(stage: "captions", after: .seconds(60)) == nil)
    }

    @Test("recognition falling silent is named, and counts are carried")
    func silentRecognition() throws {
        let pulse = Pulse()
        pulse.heard()
        pulse.translating(chars: 9)
        pulse.translated()
        let report = try #require(pulse.report(stage: "asr", after: .zero))
        #expect(report.contains("asr: STALLED"))
        #expect(report.contains("nothing recognised"))
        #expect(report.contains("heard 1"))
        #expect(report.contains("translated 1"))
    }

    @Test("silence and a broken recogniser are not the same report")
    func silenceIsNamed() throws {
        let quiet = Pulse()
        quiet.heard()
        quiet.sawAudio(peak: 0.0001)
        let hush = try #require(quiet.report(stage: "asr", after: .zero))
        #expect(hush.contains("the audio is silent"))

        let loud = Pulse()
        loud.heard()
        loud.sawAudio(peak: 0.42)
        let noise = try #require(loud.report(stage: "asr", after: .zero))
        #expect(noise.contains("audio is playing"))
        #expect(!noise.contains("silent"))
    }

    @Test("a stage that cannot hear says nothing about whether there was sound")
    func deafStageStaysQuiet() throws {
        let pulse = Pulse()
        pulse.heard()
        let report = try #require(pulse.report(stage: "captions", after: .zero))
        #expect(report.contains("nothing recognised"))
        #expect(!report.contains("silent"))
        #expect(!report.contains("playing"))
    }

    @Test("a recogniser that stops while the room does not is a stall worth acting on")
    func stalledWithSound() {
        let pulse = Pulse()
        pulse.heard()
        pulse.sawAudio(peak: 0.4)
        #expect(pulse.isStalled(after: .zero))
        // Quiet is not a stall, however long it lasts.
        let quiet = Pulse()
        quiet.heard()
        quiet.sawAudio(peak: 0.0001)
        #expect(!quiet.isStalled(after: .zero))
        // Nor is a pipeline that has not started.
        #expect(!Pulse().isStalled(after: .zero))
    }

    @Test("words arriving clear the stall, and loudness is judged since they last did")
    func hearingClearsTheStall() {
        let pulse = Pulse()
        pulse.heard()
        pulse.sawAudio(peak: 0.4)
        #expect(pulse.isStalled(after: .zero))
        pulse.heard()
        #expect(!pulse.isStalled(after: .zero))
        pulse.sawAudio(peak: 0.0001)
        #expect(!pulse.isStalled(after: .zero))
    }

    @Test("a restarted stage starts over with nothing held against it")
    func resetForgets() {
        let pulse = Pulse()
        pulse.heard()
        pulse.sawAudio(peak: 0.4)
        #expect(pulse.isStalled(after: .zero))
        pulse.reset()
        #expect(!pulse.isStalled(after: .zero))
    }

    @Test("a long limit means a working pipeline stays quiet")
    func patientLimit() {
        let pulse = Pulse()
        pulse.heard()
        pulse.translating(chars: 8)
        #expect(pulse.report(stage: "captions", after: .seconds(60)) == nil)
    }
}
