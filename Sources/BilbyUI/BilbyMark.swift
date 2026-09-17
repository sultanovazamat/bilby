import AppKit
import SwiftUI

/// One continuous silhouette: two long, unequal ears, a sloping forehead,
/// and the bilby's tapered snout.
///
/// A path rather than an image asset: one definition serves a template in the
/// menu bar and a large mark in a window, sharp at any size, tinted by the
/// system for light and dark.
///
/// Drawn as a single closed contour on purpose. Overlapping subpaths that turn
/// opposite ways cancel each other under the non-zero fill rule, which shows up
/// as white seams exactly where two shapes meet — a separate-ears version was
/// abandoned for that reason.
public struct BilbyMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        // Preserve the animal's proportions even in a non-square container.
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)
        func at(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * side, y: origin.y + y * side)
        }

        var path = Path()
        path.move(to: at(0.055, 0.735))
        // Nose → forehead → the forward, splayed ear.
        path.addCurve(to: at(0.40, 0.53), control1: at(0.17, 0.68), control2: at(0.32, 0.66))
        path.addCurve(to: at(0.24, 0.09), control1: at(0.35, 0.40), control2: at(0.23, 0.18))
        path.addCurve(to: at(0.29, 0.065), control1: at(0.24, 0.045), control2: at(0.265, 0.04))
        path.addCurve(to: at(0.61, 0.48), control1: at(0.43, 0.17), control2: at(0.56, 0.33))
        // The deep notch keeps the ears distinct at 18 points.
        path.addQuadCurve(to: at(0.67, 0.49), control: at(0.64, 0.51))
        path.addCurve(to: at(0.83, 0.055), control1: at(0.68, 0.31), control2: at(0.77, 0.10))
        path.addCurve(to: at(0.885, 0.065), control1: at(0.86, 0.02), control2: at(0.89, 0.025))
        path.addCurve(to: at(0.82, 0.565), control1: at(0.90, 0.25), control2: at(0.865, 0.43))
        // Rounded cheek and jaw, tapering all the way back to the nose.
        path.addCurve(to: at(0.84, 0.76), control1: at(0.87, 0.64), control2: at(0.875, 0.71))
        path.addCurve(to: at(0.62, 0.91), control1: at(0.80, 0.855), control2: at(0.72, 0.91))
        path.addCurve(to: at(0.32, 0.85), control1: at(0.49, 0.925), control2: at(0.40, 0.89))
        path.addLine(to: at(0.065, 0.785))
        path.addQuadCurve(to: at(0.055, 0.735), control: at(0.02, 0.765))
        path.closeSubpath()

        return path
    }

    /// macOS supplies the tint for light, dark, and highlighted menu bars.
    public static func menuBarImage(side: CGFloat = 18) -> NSImage {
        let image = NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: BilbyMark().path(in: rect).cgPath).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
