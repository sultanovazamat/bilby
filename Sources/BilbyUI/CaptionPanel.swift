import AppKit
import SwiftUI

/// The caption bar's window.
///
/// SwiftUI can express none of this: a panel that never takes focus, floats
/// above full-screen apps, lets every click through to whatever is beneath,
/// and stays out of screen recordings — so nobody in the call can tell you are
/// reading translations.
public final class CaptionPanel: NSPanel {
    public init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sharingType = .none
        ignoresMouseEvents = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
    }

    /// Bottom centre of the screen the mouse is on, like subtitles.
    public func placeAtBottom(inset: CGFloat = 90) {
        guard let screen = NSScreen.main else { return }
        let size = frame.size
        setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - size.width / 2,
            y: screen.visibleFrame.minY + inset
        ))
    }
}
