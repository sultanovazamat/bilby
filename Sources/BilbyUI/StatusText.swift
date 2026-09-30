import BilbyCore

/// Sentences for people, from states the pipeline reports in its own terms.
/// Every string a user reads about the pipeline's state is made here, so it
/// can be tested and so the raw counters and Core Audio codes stay in the log.
public enum StatusText {
    /// Before the first words arrive, in the bar and on the last setup page.
    public static func waiting(readiness: Readiness, app: String?) -> String {
        switch readiness {
        // The model is already on this Mac here, being loaded, not fetched:
        // "Getting ready…" said nothing about what the wait was, or how long.
        case .idle, .preparing(nil): return "Loading speech recognition…"
        case .preparing(let fraction?):
            return "Loading speech recognition, \(Int((fraction * 100).rounded()))%"
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
        case .noTranslation:
            return "Nothing is coming back translated. The language may need downloading again."
        case .failed(.permission): return "Bilby isn’t allowed to hear other apps."
        case .failed(.noOutputDevice):
            return "This Mac has no sound output selected, so there is nothing to listen to."
        case .failed(.appGone): return "\(app) stopped playing audio. Start captions again when it does."
        case .failed(.overloaded): return "Captions couldn’t keep up and stopped. Choose an app to restart."
        case .failed(.plumbing): return "Something went wrong. Start captions again."
        }
    }

    /// Whether the one thing a person can fix themselves is what went wrong.
    public static func isPermission(_ state: Diagnostics.State) -> Bool {
        state == .failed(.permission)
    }
}
