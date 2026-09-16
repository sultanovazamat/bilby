import SwiftUI
@preconcurrency import Translation

/// The only way to install a language pair: the SwiftUI `.translationTask`
/// path inside a real app. A plain process cannot do it — `prepareTranslation()`
/// fails in 11 ms with `.notInstalled` and downloads nothing.
///
/// This is onboarding step 3, prototyped early because nothing else can be
/// measured until it works.
@main
struct Prepare: App {
    var body: some Scene {
        WindowGroup { Screen() }
    }
}

struct Screen: View {
    @State private var configuration = TranslationSession.Configuration(
        source: Locale.Language(identifier: "en"),
        target: Locale.Language(identifier: "ru")
    )
    @State private var log = "preparing en → ru…"

    private let phrases = [
        "So let's circle back on the runway before we commit to Q3.",
        "We should ship the beta before the offsite.",
        "But the runway is tighter than we thought.",
    ]

    var body: some View {
        Text(log)
            .font(.system(.body, design: .monospaced))
            .padding()
            .frame(width: 560, alignment: .leading)
            // `session` is non-Sendable and arrives as `sending`, so it must not
            // leave this closure. Everything happens inline.
            .translationTask(configuration) { session in
                var lines: [String] = []
                func note(_ text: String) {
                    lines.append(text)
                    print(text)
                    fflush(stdout)
                }

                do {
                    let started = ContinuousClock.now
                    try await session.prepareTranslation()
                    note("prepared in \(ContinuousClock.now - started)")
                } catch {
                    note("prepare failed: \(error)")
                    return
                }

                var timings: [Double] = []
                for phrase in phrases {
                    let started = ContinuousClock.now
                    do {
                        let response = try await session.translate(phrase)
                        let elapsed = ContinuousClock.now - started
                        timings.append(Double(elapsed.components.seconds)
                                       + Double(elapsed.components.attoseconds) / 1e18)
                        note(String(format: "%.3fs  %@", timings.last!, response.targetText))
                    } catch {
                        note("failed: \(error)")
                    }
                }
                if !timings.isEmpty {
                    note(String(format: "median %.3fs", timings.sorted()[timings.count / 2]))
                }
            }
    }
}
