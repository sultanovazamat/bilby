/// How large the captions are drawn.
///
/// macOS already asks this question once, in Accessibility settings, and
/// Apple's own players honour the answer. Someone who has already said they
/// want large captions should not have to say it again here, so the default
/// is to follow that and the rest are overrides for wanting Bilby
/// specifically different.
public enum TextSize: String, CaseIterable, Sendable {
    case system
    case small
    case medium
    case large

    public var name: String {
        switch self {
        case .system: "Match System Settings"
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }

    /// `systemScale` is what macOS reports for captions, 1 when untouched.
    public func type(systemScale: Double) -> CaptionType {
        switch self {
        case .system: CaptionType(scale: systemScale)
        case .small: CaptionType(scale: 0.8)
        case .medium: CaptionType(scale: 1)
        case .large: CaptionType(scale: 1.4)
        }
    }
}

/// The sizes both caption surfaces draw at.
public struct CaptionType: Equatable, Sendable {
    /// What the app was drawn at, and what a scale of 1 means.
    public static let baseLine = 23.0
    public static let baseSource = 13.0
    public static let baseTranslation = 17.0
    public static let baseStatus = 15.0
    public static let baseWidth = 880.0
    /// Below this captions stop being glanceable; above it a line holds so
    /// few words that the bar truncates more than it shows.
    public static let smallest = 0.7
    public static let biggest = 2.0

    public let scale: Double

    public init(scale: Double) {
        self.scale = min(max(scale.isFinite ? scale : 1, Self.smallest), Self.biggest)
    }

    public var line: Double { Self.baseLine * scale }
    public var historySource: Double { Self.baseSource * scale }
    public var historyTranslation: Double { Self.baseTranslation * scale }
    public var status: Double { Self.baseStatus * scale }

    /// Bigger text in the same width is just more truncation, so the bar
    /// grows with it — up to what the screen allows.
    public func barWidth(within limit: Double) -> Double {
        min(Self.baseWidth * scale, limit)
    }
}
