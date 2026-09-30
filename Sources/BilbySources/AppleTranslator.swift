import BilbyCore
import Foundation
// TranslationSession is not Sendable. The actor below is its only owner and
// never hands it out, which the compiler cannot express.
@preconcurrency import Translation

/// Apple's on-device translation.
///
/// `TranslationSession` is not `Sendable`, so an actor owns it and nobody else
/// ever holds a reference. Measured at 0.06–0.16 s per clause once the language
/// pair is installed; installing it is onboarding's job and needs SwiftUI.
public actor AppleTranslator: Translating {
    private let source: Locale.Language
    private var sessions: [String: TranslationSession] = [:]

    public init(source: Locale.Language = Locale.Language(identifier: "en")) {
        self.source = source
    }

    public func translate(_ text: String, to language: Language) async throws -> String {
        let session =
            sessions[language.code]
            ?? {
                Log.write("translate: opening session \(source.languageCode?.identifier ?? "?") -> \(language.code)")
                let new = TranslationSession(
                    installedSource: source,
                    target: Locale.Language(identifier: language.code)
                )
                sessions[language.code] = new
                return new
            }()
        do {
            return try await session.translate(text).targetText
        } catch {
            // CaptionSession swallows failures so one bad clause cannot stall
            // the rest. Without this line it would also be invisible.
            Log.failure("translate", error: error)
            sessions[language.code] = nil
            throw error
        }
    }
}
