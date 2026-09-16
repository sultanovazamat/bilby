import Foundation

/// A language captions can be translated into. BCP-47, e.g. "ru".
public struct Language: Hashable, Sendable {
    public let code: String
    public init(_ code: String) { self.code = code }
}

/// One recognition result from the transcriber.
///
/// `text` is the whole utterance so far, not a delta: each update replaces the
/// previous one. While `isFinal` is false the wording may still change.
public struct Utterance: Equatable, Sendable {
    public let text: String
    public let isFinal: Bool
    public let at: Duration

    public init(_ text: String, isFinal: Bool = false, at: Duration = .zero) {
        self.text = text
        self.isFinal = isFinal
        self.at = at
    }
}

/// Speech that is complete enough to translate.
public struct Clause: Equatable, Sendable {
    public let text: String
    public let at: Duration
}

/// One caption line on screen. Once translated it is never rewritten.
public struct Line: Equatable, Sendable, Identifiable {
    public let id: Int
    public let source: String
    public let translation: String?
    public let at: Duration
}

extension Line {
    /// A copy carrying its translation, for presentation. `Transcript` still
    /// refuses to translate the same line twice — this only renders it.
    public func translated(_ text: String) -> Line {
        Line(id: id, source: source, translation: text, at: at)
    }
}

/// Everything the caption bar draws.
public enum CaptionEvent: Equatable, Sendable {
    /// Live source text for the top line, updating word by word.
    case live(String)
    /// A committed line. Its translation is still missing.
    case line(Line)
    /// The translation for a line that was already shown.
    case translated(Line.ID, String)
    /// A provisional translation of the sentence still being spoken. Unlike a
    /// line it may change, and it exists because waiting for the model to
    /// commit to a full stop costs 1.2 s — measured.
    case draft(String)
}

extension StringProtocol {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var wordCount: Int { split(whereSeparator: \.isWhitespace).count }
}
