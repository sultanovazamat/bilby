import BilbyCore
import SwiftUI

/// Two lines, under a strip of window controls.
///
/// The source updates continuously so the bar is visibly alive; the
/// translation lands a beat later and never changes once shown. That
/// asymmetry is what makes a 0.4 s pipeline feel instant.
///
/// The controls live in a band of their own along the top, tinted apart from
/// the text: a caption that grew into the buttons would be both unreadable
/// and unclickable.
public struct CaptionBar: View {
    private let model: CaptionModel
    private let perform: (WindowControl) -> Void

    /// One type size for both lines. The only thing separating them is
    /// colour — the source dimmer, the translation at full strength.
    private static let line = Font.system(size: 23, weight: .medium, design: .rounded)

    public init(model: CaptionModel, perform: @escaping (WindowControl) -> Void) {
        self.model = model
        self.perform = perform
    }

    private var hidden: Bool { model.pair == nil && model.status == nil }

    public var body: some View {
        VStack(spacing: 0) {
            WindowControlStrip(mode: .bar, perform: perform)

            VStack(alignment: .leading, spacing: 5) {
                if let pair = model.pair {
                    // Same size and weight as the translation: people read
                    // both, and shrinking the source turned it into
                    // decoration.
                    Text(pair.source)
                        .font(Self.line)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.head)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.interpolate)
                    if let translation = pair.translation {
                        Text(translation)
                            .font(Self.line)
                            .foregroundStyle(pair.settled ? .primary : .secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                            .contentTransition(.interpolate)
                    }
                } else if let status = model.status {
                    Label(status, systemImage: "waveform")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay {
                    // Keeps the edge readable over both a white slide and a
                    // dark video, where a plain material disappears.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .opacity(hidden ? 0 : 1)
        .scaleEffect(hidden ? 0.97 : 1, anchor: .bottom)
        .blur(radius: hidden ? 6 : 0)
        // An invisible bar must not be an invisible wall over the meeting.
        .allowsHitTesting(!hidden)
        .animation(.smooth(duration: 0.28), value: hidden)
        .animation(.smooth(duration: 0.18), value: model.pair)
    }
}
