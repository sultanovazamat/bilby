# A mark that shows what Bilby does — design

Date: 2026-09-30. Written against commit 60e1808 on `first-run-and-history-panel`.

## Problem

The mark is a bilby silhouette: one path, `BilbyMark`, drawn as the menu bar
template, the setup window's header, the setup illustration, and the app icon,
which is also the disk image's volume icon. At 18 points it reads as a bird or
a rabbit about as often as a bilby, and it says nothing about what the app does.

The replacement shows the product: sound on top, and under it two lines, like
subtitles with their translation.

## Decisions

**Five bars over two identical lines, drawn on the menu bar's own grid.** The
path is laid out in an 18-point square, the size of the menu bar image, and
scaled from there:

| Part | Geometry (points, y down) |
|---|---|
| Sound | five bars 2 wide, 2 apart, x 0–18; heights 3.5, 6.5, 8, 5, 3, centred on y 4.5 |
| Source line | 18 × 2 at y 10–12 |
| Translation line | 18 × 2 at y 15–17 — the same size as the source |

Five 2-point bars 2 points apart fill 18 points exactly, so on a 1x display
every edge of a bar and of a line falls on a whole pixel. External monitors
at 1x are common where meetings happen. The parts never touch, so the
non-zero fill rule has no overlaps to cancel. That rule is why the bilby had
to be a single contour.

**Bars, not a smooth wave.** A continuous wave was drawn and compared at menu
bar size. It reads as weather: beside the system's `water.waves`, `humidity`
and `wind` it looks like one of them, where the bars beside `waveform` and
`text.alignleft` read as sound becoming text. A 2-point stroke also cannot
curve more tightly than a 1-point radius without its inside edge folding into
a point, which limits the wave to a gentle 1.5 periods, and it staircases at
1x.

**Both lines at full strength.** The caption bar separates its two lines only
by colour, with the source dimmer. A template image can dim a line with
alpha, and that was tried over a real wallpaper. At 50% the line nearly
vanishes, at 65% it looks like a rendering fault, and at 80% it cannot be
told from 100%. The two lines are the same length and weight.

**While captions run, the bottom line gives way to a dot.** The dot is 4
points across at the bottom right. The translation line ends at 12 points to
make room, leaving 2 points clear on every side, and nothing else in the image
moves. This is the one state in which the lines differ; a dot in a corner has
to take its space from something. Two alternatives were rejected:

- Shrinking the whole mark into a corner, as the bilby did, collides at 78%.
  At the 70% that clears the dot, its bars fall off the pixel grid and blur.
- Cutting a gap around the dot, the way system symbols carry badges, gives
  the same picture with a blunt, squared end on the line.

**The setup illustration shows the mark at 64 points, and holds it still.**
At 80 points the full-width bottom line runs under the step badge in the
corner of the circle. A square glyph also needs more inset inside a circle
than an animal's silhouette did. The slight rotation that made the bilby look
as if it were sniffing would make horizontal lines look like tilting text.

**The app icon keeps its tile, and the mark keeps its lift.** The bilby sat
2% of the tile high because its mass was in its body. This mark's mass is low
as well: two solid lines of about 70 square points on the grid, under a
ragged row of bars of about 48. Centred on its box, it sags the same way, as a side-by-side
render showed. `Resources/Bilby.icns` is regenerated from
`swift run BilbyPreview --icon` with `iconutil`, and the disk image picks it
up as its volume icon unchanged.

**The onboarding screenshots are retaken by hand.** The welcome and try-it
pages show photographs of the real menu bar, because they teach where to
click. Once the icon changes, they point people at an icon that no longer
exists. The terminal this was built from cannot record the screen, so they
are retaken from the installed build. `menu-sources.png` was already out of
date: it shows a "Setup…" item removed in 2cb06dd, and none of the item icons
added in e9659f6.

## Testing

Three tests draw `BilbyMark.menuBarImage` offscreen and read its pixels. Each
fails against the bilby:

- the two caption lines are the same size;
- captions running adds a dot and moves nothing else;
- the bars stay sharp on a 1x display.

The rest is looked at, not asserted: `swift run BilbyPreview` prints the mark
at menu bar sizes, and `--output` renders every setup scene in both
appearances.
