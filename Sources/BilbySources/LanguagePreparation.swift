import SwiftUI
@preconcurrency import Translation

/// The system download sheet needs a visible SwiftUI window. Keep the session
/// inside its task; the UI receives only success or a retryable error message.
public struct LanguagePreparation: View {
    private let configuration: TranslationSession.Configuration
    private let onComplete: @MainActor (String?) -> Void

    public init(target: String, onComplete: @escaping @MainActor (String?) -> Void) {
        configuration = TranslationSession.Configuration(
            source: Locale.Language(identifier: "en"),
            target: Locale.Language(identifier: target)
        )
        self.onComplete = onComplete
    }

    public var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .translationTask(configuration) { session in
                do {
                    try await session.prepareTranslation()
                    guard !Task.isCancelled else { return }
                    onComplete(nil)
                } catch {
                    guard !Task.isCancelled else { return }
                    onComplete("The language couldn’t be prepared. Check your connection and try again.")
                }
            }
    }
}
