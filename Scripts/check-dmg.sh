#!/bin/bash
# The disk image is the first thing anyone sees of Bilby, and its appearance
# lives in metadata no compiler checks: an icon file, a flag on the volume,
# and a .DS_Store holding the window's size, its backdrop, and a position for
# every item on the volume. Any of it can vanish from a refactor of
# release.sh and the build still "succeeds" — it just hands someone a generic
# white drive with a list of files in it. So assert it.
#
# Read straight out of the image, the same way release.sh wrote it. Asking
# Finder instead means opening a window and believing the answer, which is
# both racy and destructive: Finder deletes .VolumeIcon.icns out from under
# you when it opens a window on a volume.
#
# No -e, unlike every other script here: this one is meant to report every
# regression in a run, not stop at the first. That makes `|| bad …` the only
# way a check can fail, so a bare command added below would pass in silence.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DMG="${1:-$ROOT/.build/Bilby.dmg}"
[ -f "$DMG" ] || { echo "no image at $DMG — run Scripts/release.sh"; exit 1; }
# shellcheck source=Scripts/dmg-tools.sh
. "$ROOT/Scripts/dmg-tools.sh" || exit 1

MOUNT=""
# Nothing opens a Finder window on this volume any more, so there is no one to
# wait for: if the detach fails at all, it is not going to start working.
detach() { [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -force >/dev/null 2>&1; }
trap detach EXIT

# -nobrowse, because nothing here addresses the volume through Finder any
# more: it does not need to appear in anyone's sidebar to be read.
MOUNT=$(hdiutil attach "$DMG" -noautoopen -readonly -nobrowse 2>/dev/null \
        | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)
[ -n "$MOUNT" ] || { echo "could not mount $DMG"; exit 1; }

BAD=0
ok() { echo "  ✓ $1"; }
bad() { echo "  ✗ $1"; BAD=1; }

echo "── the two icons"
[ -d "$MOUNT/Bilby.app" ] && ok "Bilby.app" || bad "Bilby.app is missing"
[ -L "$MOUNT/Applications" ] && ok "Applications shortcut" \
    || bad "Applications shortcut is missing — nothing to drag onto"

echo "── the image looks like Bilby"
[ -f "$MOUNT/.VolumeIcon.icns" ] && ok ".VolumeIcon.icns" \
    || bad ".VolumeIcon.icns is missing — Finder draws a generic white drive"
# The file alone does nothing: the volume must also carry kHasCustomIcon.
[ "$(GetFileInfo -aC "$MOUNT" 2>/dev/null)" = 1 ] \
    && ok "custom icon flag on the volume" \
    || bad "custom icon flag is not set — the icns is ignored"

echo "── the window"
"$DMG_PYTHON" - "$MOUNT" <<'PYTHON' || BAD=1
import os
import re
import subprocess
import sys

from ds_store import DSStore

mount = sys.argv[1]
# The window the artwork was drawn for, and the two points its arrow runs
# between. make-dmg-art.swift draws to the same numbers and Scripts/dmg-
# settings.py writes them; this file is the third copy on purpose, because a
# test needs an oracle it did not get from the thing it is testing.
ORIGIN = (360, 140)
WIDTH, HEIGHT = 660, 400
PLACED = {"Bilby.app": (165, 190), "Applications": (495, 190)}
# Iloc is an icon's centre, so an icon parked just past the edge still draws
# inside the window. Half a 128pt icon plus room for its label.
REACH = 96
# Everything the image is expected to carry besides the two icons. Checked
# even when absent, so that dropping one from dmg-settings.py fails here
# rather than waiting for the day macOS actually creates it.
PARKED = {".background.tiff", ".VolumeIcon.icns", ".DS_Store",
          ".fseventsd", ".Trashes"}

bad = False


def ok(message):
    print(f"  ✓ {message}")


def no(message):
    global bad
    bad = True
    print(f"  ✗ {message}")


try:
    store = DSStore.open(os.path.join(mount, ".DS_Store"), "r")
except Exception as error:
    print(f"  ✗ no readable .DS_Store — Finder would invent a window ({error})")
    sys.exit(1)

with store as entries:
    volume = {}
    located = {}
    for entry in entries:
        if entry.filename == ".":
            volume[entry.code] = entry.value
        elif entry.code == b"Iloc":
            located[entry.filename] = entry.value

window = volume.get(b"bwsp", {})
view = volume.get(b"icvp", {})

# Read as four numbers rather than matched as a string: dmgbuild's exact
# spacing is not something this check should be pinned to.
bounds = [int(n) for n in re.findall(r"-?\d+", window.get("WindowBounds", ""))]
if bounds == [*ORIGIN, WIDTH, HEIGHT]:
    ok(f"{WIDTH}×{HEIGHT}, where the artwork fits")
else:
    no(f"window is {bounds}, want {[*ORIGIN, WIDTH, HEIGHT]}")

# The backdrop has to be exactly the window it is drawn for, and it is the one
# copy of the geometry nothing else here can see. Without this, moving the
# window in dmg-settings.py and in this file — the natural edit — leaves the
# artwork silently cropped or tiled with every other assertion still green.
art = os.path.join(mount, ".background.tiff")
if not os.path.isfile(art):
    no(".background.tiff is missing")
else:
    sips = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", art],
                          capture_output=True, text=True).stdout
    size = {k: int(v) for k, v in re.findall(r"(pixelWidth|pixelHeight): (\d+)", sips)}
    if (size.get("pixelWidth"), size.get("pixelHeight")) == (WIDTH, HEIGHT):
        ok(f"the backdrop is {WIDTH}×{HEIGHT}")
    else:
        no(f"the backdrop is {size} — it will crop or tile")

if view.get("iconSize") == 128.0 and view.get("textSize") == 13.0:
    ok("128pt icons, 13pt labels")
else:
    no(f"icons are {view.get('iconSize')}pt, labels {view.get('textSize')}pt")

# Arranged by anything at all and Finder snaps every icon to its own grid,
# which silently discards the positions below.
if view.get("arrangeBy") == "none":
    ok("icons stay where they are put")
else:
    no(f"icons are arranged by {view.get('arrangeBy')!r} — positions are ignored")

alias = view.get("backgroundImageAlias", b"")
if view.get("backgroundType") == 2 and b".background.tiff" in alias:
    ok("the window points at the backdrop")
else:
    no("the window does not point at .background.tiff")

for name, position in PLACED.items():
    if located.get(name) == position:
        ok(f"{name} sits on the arrow at {position}")
    else:
        no(f"{name} is at {located.get(name)}, want {position}")

# The real assertion. A disk image always carries more than the two icons,
# all of it dot-prefixed, and a default Finder lists none of it — but anyone
# who has turned on "show hidden files" sees the lot, and Finder piles
# anything without a stored position into the top left of the window, on top
# of the artwork. There is no way to make Finder omit them, so the test is
# that every one of them is parked somewhere the window does not reach.
intruders = []
for name in sorted(set(os.listdir(mount)) | PARKED):
    if name in PLACED:
        continue
    position = located.get(name)
    if position is None:
        intruders.append(f"{name} has no stored position")
    elif (-REACH <= position[0] <= WIDTH + REACH
          and -REACH <= position[1] <= HEIGHT + REACH):
        intruders.append(f"{name} at {position}")
if intruders:
    no("these would show in the window: " + ", ".join(intruders))
else:
    ok("nothing else can appear in the window")

sys.exit(1 if bad else 0)
PYTHON

[ "$BAD" = 0 ] && echo "✓ disk image is dressed" || echo "✗ disk image is not dressed"
exit "$BAD"
