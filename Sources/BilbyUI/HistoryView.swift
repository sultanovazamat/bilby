import BilbyCore
import SwiftUI

/// Every sentence of the session, oldest at the top, for readers who want to
/// go back. The sentence being spoken sits at the bottom, dimmed, and the
/// column follows it until the reader scrolls up to read something earlier.
public struct HistoryView: View {
    private let model: CaptionModel
    private let perform: (WindowControl) -> Void
    @State private var follow = LiveFollow()

    public init(model: CaptionModel, perform: @escaping (WindowControl) -> Void) {
        self.model = model
        self.perform = perform
    }

    public var body: some View {
        VStack(spacing: 0) {
            WindowControlStrip(mode: .panel, perform: perform)
            sentences
        }
        .frame(minWidth: 280, minHeight: 240)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.primary.opacity(0.10), lineWidth: 0.5)
        }
    }

    private var sentences: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if model.lines.isEmpty, model.live.isEmpty, let status = model.status {
                        Label(status, systemImage: "waveform")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.lines) { line in
                        row(source: line.source, translation: line.translation, settled: line.translation != nil)
                            .id(line.id)
                    }
                    if !model.live.isEmpty {
                        row(source: model.live, translation: model.draft.isEmpty ? nil : model.draft, settled: false)
                            .id("live")
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(18)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            } action: { _, isAtBottom in
                follow.scrolled(toBottom: isAtBottom)
            }
            .onChange(of: model.lines.count) { if follow.isFollowing { proxy.scrollTo("end") } }
            .onChange(of: model.live) { if follow.isFollowing { proxy.scrollTo("end") } }
            // Bottom right, where a scroll view's own thumb ends: the way
            // back to what is being said now.
            .overlay(alignment: .bottomTrailing) {
                if follow.showsJump {
                    Button {
                        follow.jumped()
                        withAnimation(.smooth(duration: 0.25)) { proxy.scrollTo("end") }
                    } label: {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: Circle())
                            .overlay { Circle().strokeBorder(.primary.opacity(0.12), lineWidth: 0.5) }
                            .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(14)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .help("Jump to what is being said now")
                    .accessibilityLabel("Jump to what is being said now")
                }
            }
            .animation(.smooth(duration: 0.2), value: follow)
        }
    }

    private func row(source: String, translation: String?, settled: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(source)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            if let translation {
                Text(translation)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(settled ? .primary : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
