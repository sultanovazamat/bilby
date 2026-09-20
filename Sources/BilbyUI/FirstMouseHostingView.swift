import AppKit
import SwiftUI

/// Hosts SwiftUI in a window that never becomes key.
///
/// AppKit spends the first click on a non-key window making it key, and the
/// caption windows must never take focus from the meeting. Accepting the
/// first mouse means a button presses on the first click instead of the
/// second, with nothing stolen from the app underneath.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
