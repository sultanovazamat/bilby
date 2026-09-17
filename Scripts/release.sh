#!/bin/bash
# Builds Bilby.dmg — the drag-to-Applications disk image.
#
# /Applications matters for more than tidiness: macOS ties a privacy grant to
# the app's code hash AND its path, so an app run from Downloads and later
# moved has to ask for permission again.
#
# Signing: with a Developer ID in the keychain, pass its name as $1 and the
# image is signed and ready to notarise. Without one it is ad-hoc signed, which
# still works — a grant sticks to that exact build — but Gatekeeper warns on
# first open and the user must allow it in System Settings.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${1:-}"
STAGE="$ROOT/.build/dmg"
APP="$STAGE/Bilby.app"
DMG="$ROOT/.build/Bilby.dmg"

"$ROOT/Scripts/make-app.sh" >/dev/null
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$ROOT/.build/Bilby.app" "$APP"

if [ -n "$IDENTITY" ]; then
    echo "signing with: $IDENTITY"
    codesign --force --deep --options runtime --timestamp \
             --sign "$IDENTITY" "$APP"
else
    echo "no Developer ID given — ad-hoc signing (Gatekeeper will warn once)"
    codesign --force --deep --sign - "$APP"
fi
codesign --verify --strict "$APP" && echo "signature verified"

# The symlink is the whole interaction: drag left onto right.
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Bilby" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
echo "$DMG ($(du -h "$DMG" | cut -f1))"
