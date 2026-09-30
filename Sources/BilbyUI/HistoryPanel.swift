import AppKit
import SwiftUI

/// The side mode's window: a column that keeps every sentence.
///
/// Borderless, because it draws its own controls in the same strip the bar
/// has; resizable, because how much history fits is the reader's business.
/// Like the bar it never takes keyboard focus from the meeting and floats
/// over full-screen calls. Both show up in screenshots, recordings and screen
/// sharing: a recording of a captions app should have its captions in it.
public final class HistoryPanel: NSPanel {
    private static let autosave = "HistoryPanel"

    public init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 600),
            styleMask: [.borderless, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 280, height: 240)

        let hosting = FirstMouseHostingView(rootView: content)
        // The window's frame is the user's; the view must not push back.
        hosting.sizingOptions = [.minSize]
        contentView = hosting

        // Remembered between launches; docked to the right edge the first
        // time, the side of the screen a meeting window covers least.
        if !setFrameUsingName(Self.autosave), let screen = NSScreen.main {
            let visible = screen.visibleFrame
            setFrame(
                NSRect(x: visible.maxX - 380 - 12, y: visible.minY + 12, width: 380, height: visible.height - 24),
                display: false)
        }
        setFrameAutosaveName(Self.autosave)
    }
}
