import Testing

@testable import BilbyCore

@Suite("Pulse")
struct PulseTests {
    @Test("a pipeline that has done nothing yet is not a stalled one")
    func idleIsNotStalled() {
        let pulse = Pulse()
        #expect(pulse.report(stage: "captions", after: .zero) == nil)
    }

    @Test("a translation that has not come back is named, once, and its return is too")
    func outstandingTranslation() throws {
        let pulse = Pulse()
        pulse.heard()
        pulse.translating("the runway is tighter")
        let first = try #require(pulse.report(stage: "captions", after: .zero))
        #expect(first.contains("captions: STALLED"))
        #expect(first.contains("the runway is tighter"))
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
        pulse.translating("something")
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

    @Test("a long limit means a working pipeline stays quiet")
    func patientLimit() {
        let pulse = Pulse()
        pulse.heard()
        pulse.translating("a clause")
        #expect(pulse.report(stage: "captions", after: .seconds(60)) == nil)
    }
}
