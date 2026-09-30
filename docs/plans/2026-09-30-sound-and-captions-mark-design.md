# A mark that shows what Bilby does — design

Date: 2026-09-30. Written against commit 60e1808 on `first-run-and-history-panel`.

## Problem

The mark was a bilby silhouette: one path, `BilbyMark`, drawn as the menu bar
template, the setup window's header, the setup illustration, and the app icon,
which is also the disk image's volume icon. At 18 points it read as a bird or
a rabbit about as often as a bilby, and it said nothing about what the app
does.

The replacement shows the product: sound on top, and under it two lines, like
subtitles with their translation.

## Decisions

**Nine thin bars on one baseline, over two identical thin lines, on the menu
bar's own grid.** The path is laid out in an 18-point square, the size of the
menu bar image, and scaled from there:

| Part | Geometry (points, y down) |
|---|---|
| Sound | nine bars 1 wide, 1 apart, x 0–17; heights 3, 5, 7.5, 9, 6, 8, 5.5, 3.5, 2.5, all ending on y 10 |
| Source line | 17 × 1 at y 12–13 |
| Translation line | 17 × 1 at y 16–17 — the same size as the source |

Every stroke is a whole point wide and starts on a whole point, so on a 1x
display every straight edge falls on a whole pixel. External monitors at 1x
are common where meetings happen. The cost is width: the mark is 17 points
wide, half a point left of centre in its box. Centred, every bar would
straddle two pixels and blur to grey. The parts never touch, so the non-zero
fill rule has no overlaps to cancel. That rule is why the bilby had to be a
single contour.

**Revised the same day.** The first version had five 2-point bars centred on
a line, over 2-point lines. The owner asked for thin lines and a straight
bottom to the sound. Three thin versions were compared at menu bar size:

- 2-point bars over thin lines mixed two weights and read as a bar chart.
- Five 1-point bars were the faintest thing in the menu bar and read as a
  fence.
- Nine 1-point bars, chosen, still read as sound with a flat bottom.

Thin strokes make the mark lighter than its solid neighbours in the menu
bar. That is the trade for the look, and it was made knowingly.

**Bars, not a smooth wave.** A continuous wave was drawn and compared at menu
bar size. It reads as weather: beside the system's `water.waves`, `humidity`
and `wind` it looks like one of them, where bars beside `waveform` and
`text.alignleft` read as sound becoming text.

**Both lines at full strength.** The caption bar separates its two lines only
by colour, with the source dimmer. A template image can dim a line with
alpha, and that was tried over a real wallpaper. At 50% the line nearly
vanishes, at 65% it looks like a rendering fault, and at 80% it cannot be
told from 100%. The two lines are the same length and weight.

**While captions run, the bottom line gives way to a dot.** The dot is 3
points across at the bottom right. The translation line ends at 13 points to
make room, leaving 2 points clear of it and of the line above, and nothing
else in the image moves. This is the one state in which the lines differ; a
dot in a corner has to take its space from something. Two alternatives were
rejected for the first version and still apply:

- Shrinking the whole mark into a corner, as the bilby did, pushes its
  strokes off the pixel grid and blurs them.
- Cutting a gap around the dot, the way system symbols carry badges, gives
  the same picture with a blunt, squared end on the line.

**The setup illustration shows the mark at 64 points, and holds it still.**
At 80 points the full-width bottom line runs under the step badge in the
corner of the circle. A square glyph also needs more inset inside a circle
than an animal's silhouette did. The slight rotation that made the bilby look
as if it were sniffing would make horizontal lines look like tilting text.

**The app icon keeps its tile, and the mark keeps its lift.** The bilby sat
2% of the tile high because its mass was in its body. This mark's ink is low
as well: its centre of mass sits at about 9.9 on the 18-point grid, against a
box centre of 9, because the bars stand on a baseline just above the lines.
Centred on its box, it sags. `Resources/Bilby.icns` is regenerated from
`swift run BilbyPreview --icon` with `iconutil`, and the disk image picks it
up as its volume icon unchanged.

**The onboarding screenshots carry the new icon, pasted in.** The welcome and
try-it pages show photographs of the real menu bar, because they teach where
to click. The terminal this was built from cannot record the screen. So the
old glyph was erased from each screenshot, filled from the pixels on either
side, and `BilbyMark` itself was drawn in its place. That drawing used the
built module, at the old glyph's size and ink colour, in the screenshot's own
colour space. `menu-sources.png` is still out of date in another way: it
shows a "Setup…" item removed in 2cb06dd, and none of the item icons added in
e9659f6. A fresh capture of the open menu would fix both.

## Testing

Five tests draw `BilbyMark.menuBarImage` offscreen and read its pixels. Each
of the four that the revision changed failed against the version before it:

- the two caption lines are the same size;
- each caption line is a single point thin;
- the sound stands on one straight baseline;
- captions running adds a dot and moves nothing else;
- the bars stay sharp on a 1x display.

The rest is looked at, not asserted: `swift run BilbyPreview` prints the mark
at menu bar sizes, and `--output` renders every setup scene in both
appearances.
