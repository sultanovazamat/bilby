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
        let lines = runs(lineRows(alpha))
        try #require(lines.count == 2)
        #expect(lines[0].map { alpha[$0] } == lines[1].map { alpha[$0] })
    }

    @Test("each caption line is a single point thin")
    func linesAreThin() {
        let alpha = coverage(BilbyMark.menuBarImage(), scale: 1)
        #expect(runs(lineRows(alpha)).map(\.count) == [1, 1])
    }

    @Test("the sound stands on one straight baseline")
    func flatBaseline() throws {
        let alpha = coverage(BilbyMark.menuBarImage(), scale: 1)
        // Above the first caption line, every column that holds a bar ends
        // on the same row.
        let sound = alpha.prefix(try #require(lineRows(alpha).first))
        let bottoms = (0..<18).compactMap { x in sound.indices.last { sound[$0][x] > 0.5 } }
        #expect(bottoms.count == 9, "nine bars")
        #expect(Set(bottoms).count == 1)
    }

    @Test("captions running adds a dot and moves nothing else")
    func listeningDot() {
        let idle = coverage(BilbyMark.menuBarImage(listening: false), scale: 2)
        let live = coverage(BilbyMark.menuBarImage(listening: true), scale: 2)
        // The dot, and the end of the line that makes way for it, live in the
        // bottom-right corner: from 12 points across and 14 down.
        var moved: [String] = []
        for y in 0..<36 {
            for x in 0..<36 where (x < 24 || y < 28) && idle[y][x] != live[y][x] { moved.append("\(x),\(y)") }
        }
        // A count, not the array: a failure should say how much moved and
        // where it starts, not print hundreds of coordinates.
        #expect(moved.count == 0, "first at \(moved.prefix(3).joined(separator: "; "))")
        #expect(live[33][33] > 0.99, "the dot's centre is solid")
        #expect(live[33][28] < 0.01, "the line stops short of the dot")
    }

    @Test("the bars stay sharp on a 1x display")
    func barsOnPixelGrid() {
        let alpha = coverage(BilbyMark.menuBarImage(), scale: 1)
        // Row 8 crosses all nine bars just above their baseline: one whole
        // pixel each, and nothing partly covered in between.
        let row = alpha[8]
        #expect(row.filter { $0 > 0.99 }.count == 9)
        #expect(row.allSatisfy { $0 < 0.01 || $0 > 0.99 })
    }
}

/// A caption line covers most of its row; no row of the bars does.
private func lineRows(_ alpha: [[CGFloat]]) -> [Int] {
    alpha.indices.filter { row in alpha[row].filter { $0 > 0.5 }.count >= 14 }
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

/// Consecutive rows grouped: [12, 16] becomes [[12], [16]].
private func runs(_ rows: [Int]) -> [[Int]] {
    rows.reduce(into: []) { groups, row in
        if let last = groups.last?.last, last + 1 == row {
            groups[groups.count - 1].append(row)
        } else {
            groups.append([row])
        }
    }
}
