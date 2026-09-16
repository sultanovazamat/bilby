import BilbyCore
import SwiftUI

/// Two lines and nothing else.
///
/// The source updates continuously so the bar is visibly alive; the
/// translation lands a beat later and never changes once shown. That
/// asymmetry is what makes a 0.4 s pipeline feel instant.
public struct CaptionBar: View {
    private let model: CaptionModel

    public init(model: CaptionModel) { self.model = model }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.live.isEmpty {
                Text(model.live)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let text = model.latest?.translation ?? model.latest?.source {
                Text(text)
                    .font(.system(size: 22, weight: .medium))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .opacity(model.live.isEmpty && model.latest == nil ? 0 : 1)
        .animation(.easeOut(duration: 0.2), value: model.latest?.id)
    }
}
