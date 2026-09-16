import BilbyCore
import SwiftUI

/// Two lines and nothing else.
///
/// The source updates continuously so the bar is visibly alive; the
/// translation lands a beat later and never changes once shown. That
/// asymmetry is what makes a 0.4 s pipeline feel instant.
///
/// There are no controls here. The panel is click-through — it must never
/// swallow a click meant for the call underneath — so a button drawn on it
/// could not be pressed. Everything is driven from the menu bar.
public struct CaptionBar: View {
    private let model: CaptionModel
    @State private var appeared = false

    public init(model: CaptionModel) { self.model = model }

    private var isEmpty: Bool { model.live.isEmpty && model.latest == nil }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if !model.live.isEmpty {
                Text(model.live)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .contentTransition(.interpolate)
                    .transition(.opacity)
            }

            if let line = model.latest {
                Text(line.translation ?? line.source)
                    .font(.system(size: 23, weight: .medium, design: .rounded))
                    .foregroundStyle(line.translation == nil ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(line.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 8)),
                        removal: .opacity
                    ))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    // Keeps the edge readable over both a white slide and a
                    // dark video, where a plain material disappears.
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        }
        .opacity(isEmpty ? 0 : 1)
        .scaleEffect(isEmpty ? 0.97 : 1, anchor: .bottom)
        .blur(radius: isEmpty ? 6 : 0)
        .animation(.smooth(duration: 0.28), value: isEmpty)
        .animation(.smooth(duration: 0.22), value: model.latest?.id)
        .animation(.easeOut(duration: 0.12), value: model.live)
    }
}
