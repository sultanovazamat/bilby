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

    @Test("a long limit means a working pipeline stays quiet")
    func patientLimit() {
        let pulse = Pulse()
        pulse.heard()
        pulse.translating("a clause")
        #expect(pulse.report(stage: "captions", after: .seconds(60)) == nil)
    }
}
