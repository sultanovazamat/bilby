import BilbyCore
import Foundation
@preconcurrency import Translation

/// The languages Apple can translate English into, and whether each is ready.
///
/// Measured: `status` does distinguish `.installed` from `.supported`, so the
/// menu can tell the difference between a language you can pick right now and
/// one that costs a three-minute download. Both sides of a pair are fetched,
/// and the download itself is Apple's own sheet — it needs a window, which is
/// why choosing an uninstalled language has to open one.
public struct Languages: Sendable {
    public struct Entry: Sendable, Identifiable, Hashable {
        public let code: String
        public let name: String
        public let isInstalled: Bool
        public var id: String { code }
    }

    private static let source = Locale.Language(identifier: "en")

    public static func available() async -> [Entry] {
        let availability = LanguageAvailability()
        var entries: [Entry] = []

        for language in await availability.supportedLanguages {
            guard let code = language.languageCode?.identifier, code != "en" else { continue }
            if entries.contains(where: { $0.code == code }) { continue }
            let state = await availability.status(from: source, to: Locale.Language(identifier: code))
            entries.append(
                Entry(
                    code: code,
                    name: Locale.current.localizedString(forLanguageCode: code)?.capitalized ?? code,
                    isInstalled: state == .installed
                )
            )
        }
        // Ready first, then alphabetical: a list where the usable ones are
        // scattered among downloads is a list you have to read twice.
        return entries.sorted { ($0.isInstalled ? 0 : 1, $0.name) < ($1.isInstalled ? 0 : 1, $1.name) }
    }

    public static func isInstalled(_ code: String) async -> Bool {
        await LanguageAvailability().status(
            from: source, to: Locale.Language(identifier: code)
        ) == .installed
    }
}
