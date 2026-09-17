import AppKit
import SwiftUI

/// The bilby, drawn rather than drawn on.
///
/// A path instead of an image asset: one definition serves an 18-point
/// template in the menu bar and a large mark in a window, it stays sharp on
/// any display, and the system tints it for light and dark without a second
/// file.
///
/// The ears are the whole animal. A bilby is a small desert marsupial whose
/// ears are nearly half its body length — it finds what it cannot see by
/// listening, which is the entire point of this app.
public struct BilbyMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }

        var path = Path()

        // Ears splayed into a V — a bilby's are set wide and carried apart,
        // which is what stops the silhouette reading as a rabbit.
        path.addPath(ear(base: at(0.44, 0.52), tip: at(0.17, 0.03), spread: 0.15 * w))
        path.addPath(ear(base: at(0.64, 0.50), tip: at(0.84, 0.05), spread: 0.15 * w))

        // A compact head with a short muzzle. An earlier version ran the
        // snout to the far edge, which at 18 points read as two ears on a
        // teardrop — the ears have to dominate, because they are the animal.
        path.move(to: at(0.70, 0.50))
        path.addCurve(to: at(0.78, 0.70), control1: at(0.77, 0.54), control2: at(0.79, 0.61))
        path.addCurve(to: at(0.54, 0.88), control1: at(0.77, 0.80), control2: at(0.67, 0.88))
        path.addCurve(to: at(0.30, 0.84), control1: at(0.45, 0.88), control2: at(0.37, 0.87))
        path.addCurve(to: at(0.13, 0.76), control1: at(0.24, 0.82), control2: at(0.17, 0.80))
        path.addCurve(to: at(0.32, 0.66), control1: at(0.09, 0.72), control2: at(0.22, 0.67))
        path.addCurve(to: at(0.48, 0.52), control1: at(0.40, 0.65), control2: at(0.45, 0.59))
        path.closeSubpath()

        return path
    }

    /// A teardrop: wide where it meets the head, pointed at the tip.
    private func ear(base: CGPoint, tip: CGPoint, spread: CGFloat) -> Path {
        let dx = tip.x - base.x, dy = tip.y - base.y
        let length = max(hypot(dx, dy), 1)
        let nx = -dy / length * spread / 2, ny = dx / length * spread / 2

        var path = Path()
        let left = CGPoint(x: base.x + nx, y: base.y + ny)
        let right = CGPoint(x: base.x - nx, y: base.y - ny)
        path.move(to: left)
        path.addQuadCurve(to: tip, control: CGPoint(x: left.x + nx * 1.6, y: left.y + ny * 1.6))
        path.addQuadCurve(to: right, control: CGPoint(x: right.x - nx * 1.6, y: right.y - ny * 1.6))
        path.closeSubpath()
        return path
    }
}

extension BilbyMark {
    /// The mark as a menu bar image.
    ///
    /// Template images are drawn by the system in whatever colour the menu bar
    /// needs, so one definition covers light, dark, and a highlighted menu.
    public static func menuBarImage(side: CGFloat = 17) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: BilbyMark().path(in: rect.insetBy(dx: 0, dy: 0.5)).cgPath).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
