/// Which speech model is listening.
///
/// Two are kept so the choice can be settled by running both on the same
/// meeting rather than argued from model cards — the same reason the first
/// engine decision in this project was made by measurement.
public enum Engine: String, CaseIterable, Sendable {
    /// Parakeet Unified. English only, punctuates, 320 ms of look-ahead.
    case english
    /// Nemotron 3.5 streaming multilingual. Forty language locales, detects
    /// which is being spoken, punctuates natively, and needs a larger chunk
    /// for that punctuation to hold up over a long session.
    case multilingual

    public var name: String {
        switch self {
        case .english: "English"
        case .multilingual: "Any language"
        }
    }

    public var detail: String {
        switch self {
        case .english: "Fastest. English only."
        case .multilingual: "40 languages, detected automatically. A moment slower."
        }
    }
}
