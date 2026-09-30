import AppKit
import Testing

@testable import BilbyUI

/// The mark is judged where it is smallest and seen most: the 18-point menu
/// bar image, read back pixel by pixel.
@Suite("Mark")
struct BilbyMarkTests {
    @Test("the two caption lines are the same size")
    func linesMatch() throws {
        let alpha = coverage(BilbyMark.menuBarImage(), scale: 1)
        // A caption line covers most of its row; no row of the bars does.
        let lines = runs(alpha.indices.filter { row in alpha[row].filter { $0 > 0.5 }.count >= 14 })
        try #require(lines.count == 2)
        #expect(lines[0].map { alpha[$0] } == lines[1].map { alpha[$0] })
    }

    @Test("captions running adds a dot and moves nothing else")
    func listeningDot() {
        let idle = coverage(BilbyMark.menuBarImage(listening: false), scale: 2)
        let live = coverage(BilbyMark.menuBarImage(listening: true), scale: 2)
        // The dot, and the end of the line that makes way for it, live in the
        // bottom-right corner: from 10 points across and 14 down.
        var moved: [String] = []
        for y in 0..<36 {
            for x in 0..<36 where (x < 20 || y < 28) && idle[y][x] != live[y][x] { moved.append("\(x),\(y)") }
        }
        // A count, not the array: a failure should say how much moved and
        // where it starts, not print hundreds of coordinates.
        #expect(moved.count == 0, "first at \(moved.prefix(3).joined(separator: "; "))")
        #expect(live[32][32] > 0.99, "the dot's centre is solid")
        #expect(live[32][26] < 0.01, "the line stops short of the dot")
    }

    @Test("the bars stay sharp on a 1x display")
    func barsOnPixelGrid() {
        let alpha = coverage(BilbyMark.menuBarImage(), scale: 1)
        // The row through the bars' shared centre line: five bars of two
        // whole pixels each, and nothing partly covered in between.
        let row = alpha[4]
        #expect(row.filter { $0 > 0.99 }.count == 10)
        #expect(row.allSatisfy { $0 < 0.01 || $0 > 0.99 })
    }
}

/// The image's alpha at `scale` pixels per point, top row first.
private func coverage(_ image: NSImage, scale: Int) -> [[CGFloat]] {
    let side = Int(image.size.width) * scale
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
    NSGraphicsContext.restoreGraphicsState()
    return (0..<side).map { y in (0..<side).map { x in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 } }
}

/// Consecutive rows grouped: [10, 11, 15, 16] becomes [[10, 11], [15, 16]].
private func runs(_ rows: [Int]) -> [[Int]] {
    rows.reduce(into: []) { groups, row in
        if let last = groups.last?.last, last + 1 == row {
            groups[groups.count - 1].append(row)
        } else {
            groups.append([row])
        }
    }
}
