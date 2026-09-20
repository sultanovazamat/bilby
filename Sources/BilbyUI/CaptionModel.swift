import BilbyCore
import Observation

/// What the caption bar and the history panel show. The engine's events are
/// the only way in.
@MainActor
@Observable
public final class CaptionModel {
    /// What the bar shows: one sentence and, when there is one, its
    /// translation. Both lines always belong to the same sentence, so the
    /// reader is never shown a translation of something other than the line
    /// above it.
    public struct Pair: Equatable, Sendable {
        public let source: String
        public let translation: String?
        /// False while the translation may still change.
        public let settled: Bool

        public init(source: String, translation: String?, settled: Bool) {
            self.source = source
            self.translation = translation
            self.settled = settled
        }
    }

    /// Enough for a two-hour meeting; more than anyone scrolls back through.
    public static let historyLimit = 500

    /// Source text, updating word by word. Sub-second.
    public private(set) var live = ""
    /// Committed lines, oldest first. A line is never rewritten.
    public private(set) var lines: [Line] = []
    /// Provisional translation of the sentence being spoken. This one may
    /// change — it is shown differently so the reader knows.
    public private(set) var draft = ""
    /// The draft the last committed sentence had when it closed, shown until
    /// its settled translation lands. Without it the bar went blank for the
    /// hundred milliseconds between the two.
    public private(set) var provisional: String?
    /// Shown while the bar has no words: what Bilby is doing instead.
    public var status: String?

    public init() {}

    /// Clears everything when a session ends, so stale text does not linger.
    public func clear() {
        live = ""
        lines = []
        draft = ""
        provisional = nil
        status = nil
    }

    public var latest: Line? { lines.last }

    /// The pair switches to the sentence being spoken only once that sentence
    /// has a draft of its own. Until then the finished one stays, so the
    /// reader gets its settled translation for at least as long as the next
    /// sentence takes to reach three words.
    public var pair: Pair? {
        if !live.isEmpty, !draft.isEmpty { return Pair(source: live, translation: draft, settled: false) }
        if let latest {
            return Pair(
                source: latest.source, translation: latest.translation ?? provisional,
                settled: latest.translation != nil)
        }
        if !live.isEmpty { return Pair(source: live, translation: nil, settled: false) }
        return nil
    }

    public func apply(_ event: CaptionEvent) {
        switch event {
        case .live(let text):
            live = text
            if !text.isEmpty { status = nil }
        case .line(let line):
            lines.append(line)
            if lines.count > Self.historyLimit { lines.removeFirst(lines.count - Self.historyLimit) }
            // The draft was of the sentence that just closed. Carry it.
            provisional = draft.isEmpty ? nil : draft
            draft = ""
        case .translated(let id, let text):
            guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
            lines[index] = lines[index].translated(text)
            provisional = nil
        case .draft(let text):
            draft = text
        }
    }
}
