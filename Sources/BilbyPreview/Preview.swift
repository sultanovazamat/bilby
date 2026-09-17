import AppKit
import BilbyUI
import Foundation

/// Prints the mark as text, so it can be judged without being seen.
@main
struct Preview {
    static func main() {
        for side in [18, 32] { render(CGFloat(side)); print() }
    }

    /// The menu bar draws at 18 points. Anything that does not survive that is
    /// decoration for a window, not an icon.
    static func render(_ side: CGFloat) {
        print("── \(Int(side))pt ──")
        let size = CGSize(width: side, height: side)
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.setFill()
            NSBezierPath(cgPath: BilbyMark().path(in: rect).cgPath).fill()
            return true
        }
        guard let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else { return }
        // Two characters per pixel, so the aspect ratio survives a terminal.

        let shades = Array(" .:-=+*#%@")
        for y in 0..<bitmap.pixelsHigh {
            var line = ""
            for x in 0..<bitmap.pixelsWide {
                let alpha = bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0
                let shade = shades[min(Int(alpha * Double(shades.count - 1)), shades.count - 1)]
                line.append(shade); line.append(shade)
            }
            print(line)
        }
    }
}
