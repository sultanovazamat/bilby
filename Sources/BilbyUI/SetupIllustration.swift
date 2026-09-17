import SwiftUI

/// A small, continuous story: sound arrives, stays on the Mac, and becomes
/// readable words. The static frame tells the same story with Reduce Motion.
struct SetupIllustration: View {
    let step: SetupModel.Step
    let isReady: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 24) {
                waveform(time: time)
                    .frame(width: 66, height: 50)

                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 120, height: 120)
                    BilbyMark()
                        .fill(.primary)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(reduceMotion ? 0 : sin(time * 1.5) * 2))
                        .frame(width: 120, height: 120)
                    Image(systemName: badge)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.background)
                        .frame(width: 34, height: 34)
                        .background(.primary, in: Circle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<3) { index in
                        Capsule()
                            .fill(index == 2 ? Color.accentColor : Color.primary.opacity(0.2))
                            .frame(width: index == 1 ? 44 : 66, height: 5)
                            .opacity(reduceMotion ? 1 : 0.55 + 0.45 * (sin(time * 2 - Double(index)) + 1) / 2)
                    }
                }
                .frame(width: 66)
            }
        }
    }

    private var badge: String {
        switch step {
        case .welcome: "captions.bubble"
        case .permission: "lock.shield"
        case .language: isReady ? "checkmark" : "character.bubble"
        case .tryIt: isReady ? "checkmark" : "waveform"
        }
    }

    private func waveform(time: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<9) { index in
                let envelope = sin(Double(index + 1) / 10 * .pi)
                let pulse = reduceMotion ? 0.65 : 0.35 + 0.65 * (sin(time * 3 + Double(index) * 0.7) + 1) / 2
                Capsule()
                    .fill(Color.primary.opacity(0.35))
                    .frame(width: 3, height: 7 + 38 * envelope * pulse)
            }
        }
    }
}
