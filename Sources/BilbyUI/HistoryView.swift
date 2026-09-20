import BilbyCore
import SwiftUI

/// Every sentence of the session, oldest at the top, for readers who want to
/// go back. The sentence being spoken sits at the bottom, dimmed, and the
/// list follows it until the reader scrolls up to read something earlier.
public struct HistoryView: View {
    private let model: CaptionModel
    @State private var atBottom = true

    public init(model: CaptionModel) { self.model = model }

    public var body: some View {
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
                .padding(.top, 10)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 24
            } action: { _, isAtBottom in
                atBottom = isAtBottom
            }
            .onChange(of: model.lines.count) { if atBottom { proxy.scrollTo("end") } }
            .onChange(of: model.live) { if atBottom { proxy.scrollTo("end") } }
            .overlay(alignment: .bottom) {
                if !atBottom {
                    Button {
                        withAnimation { proxy.scrollTo("end") }
                    } label: {
                        Label("Latest", systemImage: "arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(12)
                }
            }
        }
        .frame(minWidth: 280, minHeight: 240)
        .background(.regularMaterial)
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
        .textSelection(.enabled)
    }
}
