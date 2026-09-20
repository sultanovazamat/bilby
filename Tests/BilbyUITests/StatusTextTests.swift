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
}
