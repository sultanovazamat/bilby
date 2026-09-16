import BilbyCore
import Observation

/// What the caption bar shows. The engine's events are the only way in.
@MainActor
@Observable
public final class CaptionModel {
    /// Source text, updating word by word. Sub-second.
    public private(set) var live = ""
    /// Committed lines, oldest first. A line is never rewritten.
    public private(set) var lines: [Line] = []

    /// Hidden by the menu bar. The panel stays alive so captions keep flowing
    /// underneath — reappearing is instant rather than a cold start.
    public var isHidden = false

    public init() {}

    /// Clears the bar when a session ends, so stale text does not linger.
    public func clear() {
        live = ""
        lines = []
    }

    public var latest: Line? { lines.last }

    public func apply(_ event: CaptionEvent) {
        switch event {
        case .live(let text):
            live = text
        case .line(let line):
            lines.append(line)
        case .translated(let id, let text):
            guard let index = lines.firstIndex(where: { $0.id == id }) else { return }
            lines[index] = lines[index].translated(text)
        }
    }
}
