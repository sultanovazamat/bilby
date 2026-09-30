/// How far a model load has got, when the loader cannot say.
///
/// CoreML loads the speech model onto the Neural Engine in 14–23 s from cold,
/// and reports nothing while it does, so a bare "Getting ready…" sat on screen
/// with nothing to show it was moving. The best clock available is the last
/// load on the same Mac: this is the time elapsed against how long that took.
public struct LoadEstimate: Sendable, Equatable {
    /// How long the last load on this Mac took. Nil until there has been one.
    public private(set) var expected: Duration?

    /// The most it claims before the load has actually finished, so it can
    /// never show done and then keep someone waiting.
    public static let ceiling = 0.95

    public init(expected: Duration? = nil) {
        self.expected = expected
    }

    /// The share done, in steps of 5%: an estimate is not precise to the
    /// percent, and every change redraws the menu if it is open. Nil with
    /// nothing to go on — a number with nothing behind it would be a guess.
    public func fraction(after elapsed: Duration) -> Double? {
        guard let expected, expected > .zero else { return nil }
        let steps = Int((max(elapsed / expected, 0) * 20).rounded(.down))
        return min(Double(steps) / 20, Self.ceiling)
    }

    /// A finished load is the best guide to the next one.
    public mutating func learn(_ took: Duration) {
        expected = took
    }
}
