import Foundation
import Speech
import Translation
import FoundationModels

func log(_ text: String) { print(text); fflush(stdout) }

/// Every call here is suspected of hanging, so none of them runs unbounded.
func timed<T: Sendable>(
    _ label: String,
    seconds: Double = 15,
    work: @escaping @Sendable () async -> T
) async -> T? {
    let started = ContinuousClock.now
    let result = await withTaskGroup(of: T?.self) { group in
        group.addTask { await work() }
        group.addTask { try? await Task.sleep(for: .seconds(seconds)); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
    log("\(result == nil ? "✗ TIMED OUT" : "✓") \(label) — \(ContinuousClock.now - started)")
    return result
}

@main
struct Probe {
    static func main() async {
        log("bundle id: \(Bundle.main.bundleIdentifier ?? "<none>")")

        log("\n=== 1. Speech ===")
        let supported = await timed("SpeechTranscriber.supportedLocales", work: {
            await SpeechTranscriber.supportedLocales
        })
        if let supported {
            log("  \(supported.count): \(supported.map(\.identifier).sorted().joined(separator: ", "))")
        }
        let installed = await timed("SpeechTranscriber.installedLocales", work: {
            await SpeechTranscriber.installedLocales
        })
        if let installed {
            log("  \(installed.count): \(installed.map(\.identifier).sorted().joined(separator: ", "))")
        }

        log("\n=== 2. Translation ===")
        let languages = await timed("LanguageAvailability.supportedLanguages", work: {
            await LanguageAvailability().supportedLanguages
        })
        if let languages {
            let codes = Set(languages.map { $0.languageCode?.identifier ?? "?" })
            log("  \(languages.count) locales, \(codes.count) languages: \(codes.sorted().joined(separator: ", "))")
        }
        let status = await timed("status(en -> ru)", work: {
            await LanguageAvailability().status(
                from: Locale.Language(identifier: "en"),
                to: Locale.Language(identifier: "ru")
            )
        })
        if let status { log("  \(status)") }

        log("\n=== 3. TranslationSession without SwiftUI ===")
        let session = TranslationSession(
            installedSource: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: "ru")
        )
        let phrases = [
            "so let's circle back on the runway before we commit to Q3",
            "we should ship the beta before the offsite",
            "but the runway is tighter than we thought",
        ]
        for phrase in phrases {
            let started = ContinuousClock.now
            do {
                let response = try await session.translate(phrase)
                log("  ✓ \(ContinuousClock.now - started)  \(response.targetText)")
            } catch {
                log("  ✗ \(error)")
            }
        }

        log("\n=== 3b. Which pairs are already installed? ===")
        let availability = LanguageAvailability()
        for code in ["ru", "uk", "pl", "tr", "de", "fr", "es", "ar", "hi"] {
            let state = await availability.status(
                from: Locale.Language(identifier: "en"),
                to: Locale.Language(identifier: code)
            )
            log("  en -> \(code): \(state)")
        }

        log("\n=== 4. FoundationModels ===")
        log("  availability: \(SystemLanguageModel.default.availability)")

    }
}
