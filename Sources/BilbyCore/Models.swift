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
    public var words: [SubSequence] { split(whereSeparator: \.isWhitespace) }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var wordCount: Int { split(whereSeparator: \.isWhitespace).count }
}

/// How far the speech recogniser is from being able to caption.
public enum Readiness: Equatable, Sendable {
    case idle
    /// Fetching the model, 0…1. Happens once per machine.
    case downloading(Double)
    /// Compiling for this machine. Nothing to report until it is done.
    case preparing
    case ready
    /// One sentence a person can act on. The full error is in the log.
    case failed(String)

    public var isFailure: Bool {
        if case .failed = self { return true }
        return false
    }

    /// Ready or failed: a warm-up that has finished one way or the other.
    public var isSettled: Bool { self == .ready || isFailure }
}
