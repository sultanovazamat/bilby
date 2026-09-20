import Testing

@testable import BilbyCore

@Suite("Tap watch")
struct TapWatchTests {
    @Test("a settled capture is left alone")
    func settled() {
        var watch = TapWatch(output: "speakers", processes: [95, 96])
        #expect(watch.check(output: "speakers", playing: [95]) == .fine)
        #expect(watch.check(output: "speakers", playing: []) == .fine)
    }

    @Test("sound moving to another device rebuilds at once")
    func deviceChanged() {
        var watch = TapWatch(output: "speakers", processes: [95])
        let verdict = watch.check(output: "airpods", playing: [95])
        #expect(verdict == .rebuild("the sound moved to another device"))
    }

    @Test("one reading of an unheard process is not evidence, two are")
    func flickerIsNotEvidence() {
        var watch = TapWatch(output: "speakers", processes: [95])
        #expect(watch.check(output: "speakers", playing: [201]) == .fine)
        #expect(watch.check(output: "speakers", playing: [201]) == .rebuild("the app is playing through something else"))
    }

    @Test("a tapped process playing again clears the doubt")
    func recoveryClearsStrikes() {
        var watch = TapWatch(output: "speakers", processes: [95])
        #expect(watch.check(output: "speakers", playing: [201]) == .fine)
        #expect(watch.check(output: "speakers", playing: [95, 201]) == .fine)
        #expect(watch.check(output: "speakers", playing: [201]) == .fine)
    }
}
