/// The caption history. Append-only by construction.
///
/// A line is translated at most once. Rewriting a caption that the reader has
/// already started reading is the single thing that makes live captioning feel
/// broken, so the type refuses to do it rather than relying on discipline.
public struct Transcript: Sendable {
    public private(set) var lines: [Line] = []
    /// Ids still awaiting a translation, oldest first.
    private var pending: [Line.ID] = []
    private var nextID = 0

    public init() {}

    /// The oldest line that has not been translated yet.
    public var nextPending: Line? {
        pending.first.flatMap { id in lines.first { $0.id == id } }
    }

    public mutating func append(_ clause: Clause) -> Line {
        let line = Line(id: nextID, source: clause.text, translation: nil, at: clause.at)
        lines.append(line)
        pending.append(line.id)
        nextID += 1
        return line
    }

    /// Settles a pending line. Passing `nil` gives up on it without retrying,
    /// so one failed translation can never block the ones behind it.
    /// Returns false if the line was already settled.
    @discardableResult
    public mutating func resolve(_ id: Line.ID, translation: String?) -> Bool {
        guard let slot = pending.firstIndex(of: id) else { return false }
        pending.remove(at: slot)
        guard let translation,
              let index = lines.firstIndex(where: { $0.id == id }) else { return true }
        let old = lines[index]
        lines[index] = Line(id: old.id, source: old.source, translation: translation, at: old.at)
        return true
    }
}
