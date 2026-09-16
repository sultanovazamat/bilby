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

    public init() {}

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
