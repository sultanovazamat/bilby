import SwiftUI

/// Which caption surface is on screen. They are modes, not layers: one
/// replaces the other.
public enum CaptionMode: String, Sendable {
    /// Two lines along the bottom of the screen.
    case bar
    /// A tall column keeping every sentence.
    case panel
}

/// The buttons in the strip along the top of a caption window.
///
/// The same three, in the same order and the same colours, as every other
/// window on the machine: whatever else Bilby is, its windows should not need
/// to be learned.
public enum WindowControl: String, CaseIterable, Sendable {
    case close
    case collapse
    case expand

    /// Finder greys the control that would do nothing, rather than hiding it,
    /// so the row of three never changes shape.
    public func isEnabled(in mode: CaptionMode) -> Bool {
        switch self {
        case .close: true
        case .collapse: mode == .panel
        case .expand: mode == .bar
        }
    }

    var help: String {
        switch self {
        case .close: "Stop captions"
        case .collapse: "Show captions as a bar"
        case .expand: "Show every sentence"
        }
    }

    var symbol: String {
        switch self {
        case .close: "xmark"
        case .collapse: "minus"
        case .expand: "arrow.up.left.and.arrow.down.right"
        }
    }

    /// The system's own traffic-light colours.
    var color: Color {
        switch self {
        case .close: Color(red: 1.00, green: 0.37, blue: 0.34)
        case .collapse: Color(red: 0.99, green: 0.74, blue: 0.18)
        case .expand: Color(red: 0.16, green: 0.78, blue: 0.25)
        }
    }
}

/// The band along the top of a caption window: its own area, tinted apart
/// from the text, so nothing a speaker says ever lands under the buttons.
public struct WindowControlStrip: View {
    public static let height: CGFloat = 28

    private let mode: CaptionMode
    private let perform: (WindowControl) -> Void
    @State private var hovering = false

    public init(mode: CaptionMode, perform: @escaping (WindowControl) -> Void) {
        self.mode = mode
        self.perform = perform
    }

    public var body: some View {
        HStack(spacing: 8) {
            ForEach(WindowControl.allCases, id: \.self) { button($0) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.55))
        .overlay(alignment: .bottom) {
            Rectangle().fill(.primary.opacity(0.09)).frame(height: 1)
        }
        // Glyphs appear together, on the strip, the way the system's do.
        .onHover { hovering = $0 }
    }

    private func button(_ control: WindowControl) -> some View {
        let enabled = control.isEnabled(in: mode)
        return Button { perform(control) } label: {
            Circle()
                .fill(enabled ? control.color : Color.primary.opacity(0.17))
                .frame(width: 12, height: 12)
                .overlay {
                    if enabled, hovering {
                        Image(systemName: control.symbol)
                            .font(.system(size: 6.5, weight: .bold))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(control.help)
        .accessibilityLabel(control.help)
    }
}
