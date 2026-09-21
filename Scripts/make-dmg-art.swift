// Draws the backdrop of the install window: an arrow, from where Bilby sits
// to where Applications sits. Nothing else — the two icons are the message. The icons themselves are real
// Finder icons drawn on top by Finder, so this file must leave room for them
// and stay quiet enough not to compete with them.
//
// Written at 1x and 2x under names that differ only by "@2x"; dmgbuild spots
// the pair and folds them into one TIFF, which is how a disk image background
// stays sharp on a Retina display.
//
// The size below and the two icon centres are also written in
// Scripts/dmg-settings.py, which is what actually positions the icons. That
// file owns them; this one draws to them. check-dmg.sh asserts that the
// picture produced here is the size the window expects, but it cannot tell
// whether the arrow points at the icons — so if you move them, move them in
// both places and open the image once to look.
//
// Kept light on purpose. Finder draws the icon labels in the system label
// colour, which follows the appearance of the Mac opening the image, so no
// single background can be right for both. Light is the convention.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = CGSize(width: 660, height: 400)

// Finder positions icons from the top left; Core Graphics draws from the
// bottom left. One conversion, in one place, beats flipping the context and
// then unflipping every piece of text.
func up(_ fromTop: CGFloat) -> CGFloat { size.height - fromTop }

let bilby = CGPoint(x: 165, y: up(190))
let applications = CGPoint(x: 495, y: up(190))

func arrow(_ context: CGContext, from start: CGFloat, to end: CGFloat, y: CGFloat) {
    context.setStrokeColor(CGColor(gray: 0.68, alpha: 1))
    context.setLineWidth(7)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: start, y: y))
    context.addLine(to: CGPoint(x: end - 16, y: y))
    context.strokePath()
    // A separate path for the head: a join between shaft and head renders as
    // a notch at this line width.
    context.move(to: CGPoint(x: end - 24, y: y + 17))
    context.addLine(to: CGPoint(x: end, y: y))
    context.addLine(to: CGPoint(x: end - 24, y: y - 17))
    context.strokePath()
}

func draw(scale: CGFloat, to url: URL) {
    guard let context = CGContext(
        data: nil,
        width: Int(size.width * scale), height: Int(size.height * scale),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }
    context.scaleBy(x: scale, y: scale)
    context.interpolationQuality = .high
    context.setAllowsAntialiasing(true)

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(gray: 0.925, alpha: 1), CGColor(gray: 0.98, alpha: 1)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height),
                               options: [])

    arrow(context, from: bilby.x + 96, to: applications.x - 96, y: bilby.y)

    guard let image = context.makeImage(),
          let out = CGImageDestinationCreateWithURL(
              url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("no image") }
    CGImageDestinationAddImage(out, image, [
        kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale,
    ] as CFDictionary)
    guard CGImageDestinationFinalize(out) else { fatalError("could not write \(url.path)") }
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    FileHandle.standardError.write(Data("usage: make-dmg-art.swift <1x.png> <2x.png>\n".utf8))
    exit(2)
}
draw(scale: 1, to: URL(fileURLWithPath: arguments[1]))
draw(scale: 2, to: URL(fileURLWithPath: arguments[2]))
