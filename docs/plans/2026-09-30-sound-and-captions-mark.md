# Sound and Captions Mark Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the bilby silhouette with five bars of sound over two identical caption lines, everywhere the mark is drawn.

**Architecture:** `BilbyMark` stays a single SwiftUI `Shape`, so every call site keeps working unchanged. It is laid out on the menu bar's 18-point grid and gains a `listening` flag: the bottom line gives way to the dot, so `menuBarImage` no longer shrinks the mark. The app icon is regenerated from the same path.

**Tech Stack:** Swift 6.2, SwiftUI + AppKit, SwiftPM, Swift Testing, `iconutil`.

Design: `docs/plans/2026-09-30-sound-and-captions-mark-design.md`.

Conventions for every task:
- Tests use Swift Testing (`@Test`, `#expect`). Run one suite with `swift test --filter BilbyMarkTests`; the whole suite with `swift test`.
- `./Scripts/check.sh` is the gate: tests, core purity, the release build, and the portable app. The repo configures no formatter or linter; the strict-concurrency release build is the type gate.
- The branch is `first-run-and-history-panel`. Nothing is committed unless the user asks.

---

### Task 1: The mark's tests, failing against the bilby

**Files:**
- Create: `Tests/BilbyUITests/BilbyMarkTests.swift`

**Step 1: Write the failing tests**

```swift
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
```

**Step 2: Run them to verify they fail**

Run: `swift test --filter BilbyMarkTests`
Expected: 3 failures. `menuBarImage(listening:)` already exists, so this compiles against the bilby:
- `linesMatch` fails its `#require`: the silhouette has no pair of line rows.
- `listeningDot` fails: the bilby shrinks to 78%, so nearly every pixel moves.
- `barsOnPixelGrid` fails: row 4 crosses the ears on partial pixels.

---

### Task 2: The new mark

**Files:**
- Modify: `Sources/BilbyUI/BilbyMark.swift` (whole file)

**Step 1: Replace the silhouette**

```swift
import AppKit
import SwiftUI

/// Sound above the two lines it becomes: what was said, and its translation.
///
/// A path rather than an image asset: one definition serves a template in the
/// menu bar and a large mark in a window, sharp at any size, tinted by the
/// system for light and dark.
///
/// Laid out on the menu bar's own 18-point grid. Five 2-point bars 2 points
/// apart fill it exactly, so at 1x every straight edge falls on a whole pixel.
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
            CGRect(x: origin.x + x * unit, y: origin.y + y * unit, width: width * unit, height: height * unit)
        }

        var path = Path()
        // Every part is 2 points across, so a 1-point radius makes each end a
        // true semicircle — circular, where SwiftUI's default is continuous.
        func capsule(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            path.addRoundedRect(
                in: box(x, y, width, height), cornerSize: CGSize(width: unit, height: unit), style: .circular)
        }
        // Sound, in heights that rise and fall like speech.
        for (index, height) in [3.5, 6.5, 8, 5, 3].enumerated() {
            capsule(CGFloat(index) * 4, 4.5 - height / 2, 2, height)
        }
        // What was said, and its translation: the same size.
        capsule(0, 10, 18, 2)
        capsule(0, 15, listening ? 12 : 18, 2)
        // 2 points clear of both lines, so nothing else has to move.
        if listening { path.addEllipse(in: box(14, 14, 4, 4)) }
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
```

**Step 2: Run the tests to verify they pass**

Run: `swift test --filter BilbyMarkTests`
Expected: 3 tests pass.

---

### Task 3: The setup illustration holds a smaller mark still

**Files:**
- Modify: `Sources/BilbyUI/SetupIllustration.swift:21-25`

**Step 1: Size the mark for a circle with a badge in it, and stop the wobble**

Replace:

```swift
                    BilbyMark()
                        .fill(.primary)
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(reduceMotion ? 0 : sin(time * 1.5) * 2))
                        .frame(width: 120, height: 120)
```

with:

```swift
                    // 64, not 80: the mark is square, and any larger its
                    // bottom line runs under the badge.
                    BilbyMark()
                        .fill(.primary)
                        .frame(width: 64, height: 64)
                        .frame(width: 120, height: 120)
```

`time` and `reduceMotion` are still used by the waveform and the lines.

**Step 2: Build**

Run: `swift build`
Expected: builds with no new warnings.

---

### Task 4: The icon and the preview describe a mark, not an animal

**Files:**
- Modify: `Sources/BilbyPreview/Icon.swift:10` and `:29-30` (comments only; the placement code is unchanged)
- Modify: `Sources/BilbyPreview/Preview.swift:7`

**Step 1: Edit the comments**

- `Icon.swift:10`: "recognisably the same animal" → "recognisably the same mark".
- `Icon.swift:29-30`: "The mark sits slightly high: its mass is in the body, and centring by bounding box reads as sagging." → "The mark sits slightly high: its mass is in the two solid lines under a ragged row of bars, and centring by bounding box reads as sagging." A side-by-side render of centred, 1% and 2% kept the 2% lift.
- `Preview.swift:7`: "checks the silhouette at actual menu-bar sizes" → "checks the mark at actual menu-bar sizes".

---

### Task 5: Regenerate the app icon

**Files:**
- Modify: `Resources/Bilby.icns` (binary)

**Step 1: Render the iconset, check it, convert it, and clean up**

```bash
swift run BilbyPreview --icon                               # writes ./Bilby.iconset
for f in Bilby.iconset/*.png; do echo "$(basename $f) $(sips -g pixelWidth "$f" | awk '/pixelWidth/{print $2}')"; done
iconutil -c icns Bilby.iconset -o Resources/Bilby.icns
rm -rf Bilby.iconset
```

Expected: ten PNGs of 16, 32, 32, 64, 128, 256, 256, 512, 512 and 1024 pixels (the current icns has exactly these), then `iconutil` exits silently.

---

### Task 6: Look at it, then run the gate

**Step 1: The mark as text at menu bar sizes**

Run: `swift run BilbyPreview`
Expected: 18 pt idle shows five bars over two full-width lines. 18 pt listening shows the same bars and first line, with a shorter second line and a dot. 32 pt shows the idle mark.

**Step 2: Every scene as images**

Run: `swift run BilbyPreview --output <scratch>/previews`
Look at: `bilby-mark.png` (18/24/32/80 pt, light and dark); `setup-welcome-*` (the 22 pt header); `setup-permission-*` and `setup-language-*` (the illustration, with the badge clear of the bottom line).

**Step 3: The gate**

Run: `./Scripts/check.sh`
Expected: the test line reports every test passing; core purity is ok; "✓ release builds"; the portable-app check passes.

**Step 4: The built app carries the new icon**

Run: `iconutil -c iconset ~/Applications/Bilby.app/Contents/Resources/Bilby.icns -o <scratch>/built.iconset`, then look at `icon_128x128@2x.png`.

---

### Task 7 (user): Retake the onboarding screenshots

**Files:**
- Replace: `Sources/BilbyUI/Resources/menu-bar.png` (welcome page; today 662 × 174 px)
- Replace: `Sources/BilbyUI/Resources/menu-sources.png` (try-it page; today 804 × 388 px)

These need Screen Recording, which the terminal does not have. With the new build installed and running:
- `menu-bar.png`: the menu bar from just left of Bilby's icon to past Control Center, with a strip of desktop below, as today.
- `menu-sources.png`: the Bilby menu open with "Listen to" expanded to show apps, as today.

Both are shown fitted into a 152-point-high frame, so a similar aspect ratio keeps them the same size on the page.
