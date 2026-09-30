import AppKit
import SwiftUI

/// Sound above the two lines it becomes: what was said, and its translation.
///
/// A path rather than an image asset: one definition serves a template in the
/// menu bar and a large mark in a window, sharp at any size, tinted by the
/// system for light and dark.
///
/// Laid out on the menu bar's own 18-point grid, in strokes one point thin:
/// nine bars one point apart, standing on a single baseline, over two lines.
/// Integer bar heights keep their caps equally sharp; two-point clear gaps
/// tie the sound and both caption lines into one compact silhouette.
/// At 1x every straight edge falls on a whole pixel. That makes the mark 17
/// points wide, and it stays half a point left of centre on purpose — centred,
/// every bar would straddle two pixels and blur to grey.
/// No two parts touch: overlapping subpaths that turn opposite ways cancel
/// each other under the non-zero fill rule, which is why the bilby this
/// replaced had to be drawn as a single contour.
public struct BilbyMark: Shape {
    private let listening: Bool

    /// While captions run, the translation line gives way to a dot.
    public init(listening: Bool = false) {
        self.listening = listening
    }

    public func path(in rect: CGRect) -> Path {
        // Preserve the mark's proportions even in a non-square container.
        let side = min(rect.width, rect.height)
        let unit = side / 18
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(
                x: origin.x + x * unit, y: origin.y + y * unit, width: width * unit, height: height * unit)
        }

        var path = Path()
        // Every part is 1 point across, so a half-point radius makes each end
        // a true semicircle — circular, where SwiftUI's default is continuous.
        func capsule(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            path.addRoundedRect(
                in: box(x, y, width, height), cornerSize: CGSize(width: unit / 2, height: unit / 2),
                style: .circular)
        }
        // Sound, rising and falling like speech above a straight baseline.
        for (index, height) in [3, 5, 7, 9, 8, 5, 7, 4, 3].enumerated() {
            capsule(CGFloat(index) * 2, 10 - CGFloat(height), 1, CGFloat(height))
        }
        // What was said, and its translation: the same size.
        capsule(0, 12, 17, 1)
        capsule(0, 15, listening ? 13 : 17, 1)
        // A 2-point gap separates the shortened line from the listening dot.
        if listening { path.addEllipse(in: box(15, 14, 3, 3)) }
        return path
    }

    /// macOS supplies the tint for light, dark, and highlighted menu bars.
    /// While captions run a dot sits where the translation line ends: the
    /// only place a menu bar app can say "on" without words.
    public static func menuBarImage(side: CGFloat = 18, listening: Bool = false) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: BilbyMark(listening: listening).path(in: rect).cgPath).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
