# How the install window looks. release.sh passes the paths in with -D.
#
# This is read by dmgbuild, which writes the window's appearance straight into
# the volume's .DS_Store. The alternative — telling Finder to arrange a window
# and then trusting what it did — was what this replaced, for two reasons that
# are not style preferences:
#
#   1. Finder deletes .VolumeIcon.icns, and clears the volume's custom-icon
#      flag, when it opens a window on the volume. Measured: the icon was
#      written, Finder ran, the icon was gone. The disk image shipped with a
#      generic white drive on it for as long as that ordering stood.
#   2. Finder can only position items it is willing to show, and whether it
#      shows a dot-file depends on a per-machine setting. So a build on a
#      machine with hidden files shown produced a different window from the
#      same commit built on a machine without.
#
# Nothing here talks to Finder, so neither happens.

import os.path

application = defines["app"]
appname = os.path.basename(application)

# UDZO is what this image has always been. UDBZ is dmgbuild's default and is
# smaller, but it is also slower to open, and an install window that takes a
# beat to appear reads as a slow app.
format = "UDZO"
compression_level = 9

files = [application]
# The symlink is the whole interaction: drag left onto right.
symlinks = {"Applications": "/Applications"}

# A volume shows a custom icon only when it holds a file by this exact name
# and carries the custom-icon flag; dmgbuild does both.
icon = defines["volume_icon"]

# Pointed at the 1x drawing. dmgbuild finds background@2x.png beside it on its
# own and folds the pair into one HiDPI TIFF, which is how the backdrop stays
# sharp on a Retina display. It lands on the volume as /.background.tiff.
background = defines["background"]

# Matches the artwork exactly; anything else crops it or tiles it. This is the
# window's frame rather than its content area, so the title bar covers the top
# of the backdrop and its bottom ~28pt are never seen; nothing that has to be
# read should be drawn down there.
window_rect = ((360, 140), (660, 400))
# Load-bearing on the artwork, which is why this one is written out even
# though it is also the default: make-dmg-art.swift stops the arrow 96pt short
# of each icon's centre, and 96 is half of this plus a 32pt gap. Change it here
# and the arrow overlaps the icons or falls short of them.
icon_size = 128
text_size = 13
# The rest of the window — icon view, nothing auto-arranged, labels underneath,
# and no toolbar, sidebar, path bar, tab bar or status bar — is already what
# dmgbuild does when it is not told otherwise. Repeating it here would only
# create a second place to keep correct.

# The two icons sit on the ends of the arrow the artwork draws. These are the
# positions Finder stores and draws, in the window's own coordinates, measured
# from its top left — the same numbers make-dmg-art.swift draws the arrow
# between. Writing the .DS_Store directly means they are also the numbers that
# come back out; asking Finder to set a position stored one 45pt lower.
#
# Everything else on the volume is parked far outside the window. A disk image
# carries more than the two icons — the backdrop and the volume icon have to
# live somewhere — and all of it is dot-prefixed, so a default Finder never
# lists it. But a person who has turned on "show hidden files" sees the lot,
# and Finder auto-arranges anything without a stored position into the top
# left, which is exactly where the artwork is. Giving them a position off the
# canvas is how appdmg, DropDMG and every other disk image that looks right
# handles this; there is no way to make Finder omit them.
#
# .fseventsd and .Trashes are insurance rather than observed: the shipped
# image is read-only, so macOS cannot write either onto it, and dmgbuild
# deletes .Trashes from its own writable working volume before sealing it.
# The exposure is that working volume — macOS puts .fseventsd on any writable
# volume about a second after mounting it, and dmgbuild does not remove that
# one. It currently finishes first. A position is written whether or not the
# file exists, so pinning them costs two lines and stops that race mattering.
icon_locations = {
    appname: (165, 190),
    "Applications": (495, 190),
    ".background.tiff": (900, 900),
    ".VolumeIcon.icns": (900, 1000),
    ".fseventsd": (900, 1100),
    ".Trashes": (900, 1200),
    ".DS_Store": (900, 1300),
}
