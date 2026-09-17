import AppKit
import SwiftUI

/// The one ordinary window Bilby has.
///
/// It exists because two things cannot happen anywhere else: the system's
/// language-download sheet needs a window to appear over, and a permission
/// that is refused needs somewhere to explain itself. The caption bar cannot
/// serve — it is click-through by design.
///
/// Closing is allowed but the traffic lights are trimmed to it: there is no
/// half-finished state worth minimising, and zooming a setup window is noise.
public final class SetupWindow: NSWindow, NSWindowDelegate {
    private let onClose: () -> Void

    public init(content: some View, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 580),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        delegate = self
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        contentView = NSHostingView(rootView: content)
        center()
    }

    public func windowWillClose(_ notification: Notification) {
        onClose()
    }

    /// A menu bar app has no Dock icon, so showing a window does not bring the
    /// app forward on its own.
    public func present() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }
}
