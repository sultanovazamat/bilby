import BilbyCore

/// Sentences for people, from states the pipeline reports in its own terms.
/// Every string a user reads about the pipeline's state is made here, so it
/// can be tested and so the raw counters and Core Audio codes stay in the log.
public enum StatusText {
    /// Before the first words arrive, in the bar and on the last setup page.
    public static func waiting(readiness: Readiness, app: String?) -> String {
        switch readiness {
        case .idle, .preparing: return "Getting ready…"
        case .downloading(let fraction):
            return "Downloading speech recognition, \(Int((fraction * 100).rounded()))%"
        case .failed(let message): return message
        case .ready: return app.map { "Listening to \($0)…" } ?? "Listening…"
        }
    }

    /// While captions run: the first stage that is empty, or nil when words
    /// are flowing. A running app should not narrate itself.
    public static func problem(_ state: Diagnostics.State, app: String) -> String? {
        switch state {
        case .flowing: return nil
        case .noAudio: return "No sound from \(app) yet. Is it muted?"
        case .noSpeech: return "Listening, no speech heard yet"
        case .noSentence: return "Listening…"
        case .failed(let reason) where isPermission(reason): return "Bilby isn’t allowed to hear other apps."
        case .failed: return "Something went wrong. Start captions again."
        }
    }

    /// A tap that could not be created is, in practice, a tap macOS refused.
    public static func isPermission(_ reason: String) -> Bool { reason.hasPrefix("create tap") }
}
