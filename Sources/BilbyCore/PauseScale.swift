import Foundation

/// How long this speaker pauses when they finish a thought.
///
/// A fixed threshold cannot work. What counts as a long silence depends on
/// who is talking and on the material: a fast presenter's sentence break is
/// shorter than a hesitant conversationalist's mid-sentence hesitation, so
/// any single number cuts one of them in the wrong place. This measures the
/// gaps this speaker is actually leaving and puts the boundary where their
/// own longest gaps begin.
///
/// The quantile is the whole idea. Sentences run around a dozen words, so
/// roughly one gap in twelve is a sentence end; taking the threshold near
/// that point in the distribution makes the rule cut at about sentence rate
/// whoever is speaking, without being told anything about them.
public struct PauseScale: Sendable, Equatable {
    /// Gaps kept. About a minute of speech, so the scale follows a change of
    /// speaker rather than averaging over the whole meeting.
    public static let remembered = 150
    /// Below this, evidence is too thin to prefer over a plain guess.
    public static let leastEvidence = 25
    /// What to use until there is enough.
    public static let untilKnown: TimeInterval = 0.6
    /// However fast the speech, a gap this short is a breath, not a sentence.
    public static let shortest: TimeInterval = 0.3
    /// However halting, waiting longer than this strands the reader.
    public static let longest: TimeInterval = 1.2
    /// The share of gaps treated as sentence ends.
    private static let quantile = 0.92

    private var gaps: [TimeInterval] = []
    private var next = 0

    public init() {}

    public mutating func saw(gap: TimeInterval) {
        guard gap.isFinite, gap >= 0 else { return }
        if gaps.count < Self.remembered {
            gaps.append(gap)
        } else {
            gaps[next] = gap
            next = (next + 1) % Self.remembered
        }
    }

    /// The gap that ends a sentence, for the person talking now.
    public var boundary: TimeInterval {
        guard gaps.count >= Self.leastEvidence else { return Self.untilKnown }
        let sorted = gaps.sorted()
        let position = Self.quantile * Double(sorted.count - 1)
        let low = Int(position.rounded(.down))
        let high = min(low + 1, sorted.count - 1)
        let estimate = sorted[low] + (sorted[high] - sorted[low]) * (position - Double(low))
        return min(max(estimate, Self.shortest), Self.longest)
    }
}
