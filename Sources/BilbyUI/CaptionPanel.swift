import AppKit
import SwiftUI

/// The caption bar's window.
///
/// SwiftUI can express none of this: a panel that never takes focus, floats
/// above full-screen apps. Captions may appear in screen recordings and
/// screen sharing; macOS provides no reliable exclusion for these windows.
///
/// It stopped being click-through when it grew buttons: a control drawn on a
/// window that ignores the mouse cannot be pressed. Dragging it anywhere is
/// what replaces clicking through it.
public final class CaptionPanel: NSPanel, NSWindowDelegate {
    private static let autosave = "CaptionBar"

    /// The corner the bar is pinned to.
    ///
    /// Its height changes with every sentence, so its position has to be
    /// stated absolutely each time. Deriving it from the frame the last
    /// resize happened to leave behind is a feedback loop: `NSHostingView`
    /// resizes a window anchored to its top while this class anchors to the
    /// bottom, and the two disagreeing walked the bar two hundred thousand
    /// points below the screen over one meeting.
    private var anchor: NSPoint = .zero

    public init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 124),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // Best effort for legacy capture APIs, not a privacy boundary.
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true

        // Deliberately not `.preferredContentSize`: that makes the hosting
        // view a second thing that resizes the window, anchored to the
        // opposite edge from `fitContent`. One resize path, one anchor.
        contentView = FirstMouseHostingView(rootView: content)
        delegate = self

        if !setFrameUsingName(Self.autosave) || !isSomewhereVisible {
            placeAtBottom()
        }
        anchor = frame.origin
        setFrameAutosaveName(Self.autosave)
    }

    /// A position saved on a display that is no longer attached — or one that
    /// drifted before this class pinned it — must not leave the bar somewhere
    /// its owner cannot find it.
    private var isSomewhereVisible: Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
    }

    /// Bottom centre, like subtitles everywhere: shortest path for the eye
    /// between the speaker and the text. A corner would add a diagonal journey
    /// to every sentence, and the top right belongs to notifications anyway.
    /// Only until the bar is dragged somewhere its owner prefers.
    public func placeAtBottom(inset: CGFloat = 90) {
        guard let screen = NSScreen.main else { return }
        setFrameOrigin(
            NSPoint(
                x: screen.visibleFrame.midX - frame.width / 2,
                y: screen.visibleFrame.minY + inset
            ))
        anchor = frame.origin
    }

    /// Wider text needs a wider bar, or bigger type only means more of the
    /// sentence cut off. Grows about its own centre rather than its corner,
    /// because a bar is read where it sits.
    public func setWidth(_ width: CGFloat) {
        guard abs(width - frame.width) > 0.5 else { return }
        let centre = frame.midX
        anchor = NSPoint(x: centre - width / 2, y: anchor.y)
        setFrame(
            NSRect(x: anchor.x, y: anchor.y, width: width, height: frame.height), display: true)
        fitContent()
    }

    /// Grows upward from the anchor, so a second line pushes the first one up
    /// rather than dragging the bar down over whatever it was placed to avoid.
    public func fitContent() {
        guard let hosting = contentView else { return }
        let ideal = hosting.fittingSize.height
        // A view that has not been laid out yet reports nothing, and
        // believing it collapses the bar to a sliver.
        guard ideal > 1 else { return }
        let target = NSRect(x: anchor.x, y: anchor.y, width: frame.width, height: ideal)
        guard target != frame else { return }
        setFrame(target, display: true)
    }

    /// Dragging the bar chooses a new anchor. Resizing it does not: AppKit
    /// posts this for moves, and a resize that shifts the origin arrives as
    /// `windowDidResize` alone — measured, because the difference is the
    /// whole bug this anchor exists to prevent.
    public func windowDidMove(_ notification: Notification) {
        anchor = frame.origin
    }
}
