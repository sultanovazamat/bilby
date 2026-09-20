import AppKit
import SwiftUI

/// The side mode's window: a column that keeps every sentence.
///
/// Unlike the bar it must take scroll events, so it is not click-through.
/// Like the bar it never takes keyboard focus from the meeting, floats over
/// full-screen calls, and stays out of screen sharing.
public final class HistoryPanel: NSPanel {
    /// Closing the panel with its button is switching back to the bar.
    public var onClose: (() -> Void)?

    public init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        sharingType = .none
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        minSize = NSSize(width: 280, height: 240)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        let hosting = NSHostingView(rootView: content)
        // The window's frame is the user's; the view must not push back.
        hosting.sizingOptions = [.minSize]
        contentView = hosting

        // Remembered between launches; docked to the right edge the first
        // time, the side of the screen a meeting window covers least.
        if !setFrameUsingName("HistoryPanel"), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrame(
                NSRect(x: visible.maxX - 380 - 12, y: visible.minY + 12, width: 380, height: visible.height - 24),
                display: false)
        }
        setFrameAutosaveName("HistoryPanel")
    }

    public override func close() {
        super.close()
        onClose?()
    }
}
