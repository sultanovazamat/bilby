#!/bin/bash
# Builds Bilby.dmg — the drag-to-Applications disk image.
#
# /Applications matters for more than tidiness: macOS ties a privacy grant to
# the app's code hash AND its path, so an app run from Downloads and later
# moved has to ask for permission again.
#
# Signing: with a Developer ID in the keychain, pass its name as $1 and the
# image is signed. Set BILBY_NOTARY_PROFILE as well and it is notarised and
# stapled, which is what makes the first open an ordinary double-click. Store
# the profile once with:
#   xcrun notarytool store-credentials bilby \
#       --apple-id <you> --team-id <team> --password <app-specific password>
# Without a Developer ID the app is ad-hoc signed, which still works — a
# privacy grant sticks to that exact build — but Gatekeeper refuses the first
# open, so the image carries a note telling the recipient what to do.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${1:-}"
NOTARY_PROFILE="${BILBY_NOTARY_PROFILE:-}"
STAGE="$ROOT/.build/dmg"
APP="$STAGE/Bilby.app"
DMG="$ROOT/.build/Bilby.dmg"

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
# Build straight into the staging folder: the image must hold the app that
# was just built, not whatever an earlier run left in .build.
BILBY_CONFIG=release BILBY_APP_PATH="$APP" "$ROOT/Scripts/make-app.sh" >/dev/null
"$ROOT/Scripts/check-app-portable.sh" "$APP"

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

# An unnotarised app is refused on first open with no obvious way forward.
# Saying so in the image beats leaving someone to conclude Bilby is broken.
if [ -z "$NOTARY_PROFILE" ]; then
    cat > "$STAGE/Open me first.txt" <<'NOTE'
Bilby is not signed by Apple yet, so the first time you open it macOS says it
cannot check it for malicious software. Getting past that takes four steps,
once:

  1. Drag Bilby onto the Applications folder beside it.
  2. Open your Applications folder and double-click Bilby. macOS refuses.
  3. Open System Settings, go to Privacy & Security, scroll to the bottom,
     and click "Open Anyway" next to Bilby.
  4. Confirm. From now on Bilby opens like anything else.

Bilby has no icon in the Dock. Look for the small animal in the menu bar, at
the top right of your screen, near the clock.
NOTE
fi

hdiutil create -volname "Bilby" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

if [ -n "$IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "notarising (this waits on Apple, usually a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "notarised and stapled"
elif [ -n "$IDENTITY" ]; then
    echo "signed but not notarised — set BILBY_NOTARY_PROFILE to notarise"
fi

echo "$DMG ($(du -h "$DMG" | cut -f1))"
