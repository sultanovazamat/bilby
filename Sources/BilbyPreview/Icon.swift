import AppKit
import BilbyUI
import SwiftUI

/// Renders the app icon from the same path as the menu bar mark.
///
/// One definition, two very different jobs: the menu bar wants a bare
/// monochrome template, while Finder and the Dock want a rounded tile that
/// sits among the system's own icons without looking like a sticker. Drawing
/// both from the same shape is what keeps them recognisably the same mark.
enum Icon {
    /// macOS rounds app icons itself only for the ones it draws; ours supplies
    /// its own tile, inset the way Apple's are so it does not look oversized
    /// beside them.
    static func image(side: CGFloat) -> NSImage {
        NSImage(size: CGSize(width: side, height: side), flipped: true) { rect in
            let inset = side * 0.086
            let tile = rect.insetBy(dx: inset, dy: inset)
            let radius = tile.width * 0.2237  // Rounded tile corner proportion

            let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
            NSGradient(
                colors: [
                    NSColor(calibratedRed: 0.08, green: 0.18, blue: 0.44, alpha: 1),
                    NSColor(calibratedRed: 0.19, green: 0.38, blue: 0.72, alpha: 1),
                ]
            )?.draw(in: path, angle: -90)

            // A quiet inset highlight defines the tile without a drop shadow
            // or a second silhouette at the small Finder sizes.
            let rimWidth = side / 512
            let rim = NSBezierPath(
                roundedRect: tile.insetBy(dx: rimWidth / 2, dy: rimWidth / 2),
                xRadius: radius - rimWidth / 2, yRadius: radius - rimWidth / 2)
            rim.lineWidth = rimWidth
            NSColor(calibratedWhite: 1, alpha: 0.14).setStroke()
            rim.stroke()

            // The mark sits slightly high: most of its ink is in its lower
            // half, where the bars stand on their baseline over the lines, and
            // centring by bounding box reads as sagging.
            // Its ink spans 17 of the grid's 18 points. Compensate for that
            // half-point offset here, where menu-bar pixel alignment is not
            // needed, so the tile has equal left and right optical margins.
            let markSide = tile.width * 0.60
            let mark = CGRect(
                x: tile.midX - markSide / 2 + markSide / 36,
                y: tile.midY - markSide / 2 - tile.height * 0.02,
                width: markSide,
                height: markSide
            )
            NSColor(calibratedRed: 0.94, green: 0.97, blue: 1.00, alpha: 1).setFill()
            NSBezierPath(cgPath: BilbyMark().path(in: mark).cgPath).fill()
            return true
        }
    }

    static func writeIconSet(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let side = CGFloat(size * scale)
                guard let data = image(side: side).tiffRepresentation,
                    let bitmap = NSBitmapImageRep(data: data),
                    let png = bitmap.representation(using: .png, properties: [:])
                else { continue }
                let suffix = scale == 1 ? "" : "@2x"
                let name = "icon_\(size)x\(size)\(suffix).png"
                try png.write(to: directory.appendingPathComponent(name))
            }
        }
    }
}
