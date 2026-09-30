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
            let radius = tile.width * 0.2237  // Apple's squircle proportion

            let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)
            NSGradient(
                colors: [
                    NSColor(calibratedRed: 0.99, green: 0.93, blue: 0.84, alpha: 1),
                    NSColor(calibratedRed: 0.93, green: 0.78, blue: 0.60, alpha: 1),
                ]
            )?.draw(in: path, angle: -90)

            // The mark sits slightly high: most of its ink is in its lower
            // half, where the bars stand on their baseline over the lines, and
            // centring by bounding box reads as sagging.
            let markSide = tile.width * 0.58
            let mark = CGRect(
                x: tile.midX - markSide / 2,
                y: tile.midY - markSide / 2 - tile.height * 0.02,
                width: markSide,
                height: markSide
            )
            NSColor(calibratedRed: 0.20, green: 0.13, blue: 0.08, alpha: 1).setFill()
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
