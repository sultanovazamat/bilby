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
}
