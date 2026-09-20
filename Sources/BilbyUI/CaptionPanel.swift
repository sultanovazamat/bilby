import AppKit
import SwiftUI

/// The caption bar's window.
///
/// SwiftUI can express none of this: a panel that never takes focus, floats
/// above full-screen apps, and stays out of screen recordings — so nobody in
/// the call can tell you are reading translations.
///
/// It stopped being click-through when it grew buttons: a control drawn on a
/// window that ignores the mouse cannot be pressed. Dragging it anywhere is
/// what replaces clicking through it.
public final class CaptionPanel: NSPanel {
    private static let autosave = "CaptionBar"

    public init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 124),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true

        let hosting = FirstMouseHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting

        if !setFrameUsingName(Self.autosave) { placeAtBottom() }
        setFrameAutosaveName(Self.autosave)
    }

    /// Bottom centre, like subtitles everywhere: shortest path for the eye
    /// between the speaker and the text. A corner would add a diagonal journey
    /// to every sentence, and the top right belongs to notifications anyway.
    /// Only for the first run; after that the bar is wherever it was left.
    public func placeAtBottom(inset: CGFloat = 90) {
        guard let screen = NSScreen.main else { return }
        setFrameOrigin(
            NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.minY + inset
            ))
    }

    /// Grows upward from wherever the bar sits: the bottom edge is the anchor,
    /// so a second line pushes the first one up rather than dragging the whole
    /// bar down over what it was placed to avoid.
    public func fitContent() {
        guard let hosting = contentView else { return }
        let height = max(hosting.fittingSize.height, 1)
        guard abs(height - frame.height) > 0.5 else { return }
        setFrame(
            NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: height),
            display: true)
    }
}
