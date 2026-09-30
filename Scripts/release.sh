#!/bin/bash
# Builds Bilby.dmg — the drag-to-Applications disk image.
#
# /Applications matters for more than tidiness: macOS ties a privacy grant to
# the app's code hash AND its path, so an app run from Downloads and later
# moved has to ask for permission again.
#
# Everything that makes the image look like anything — the volume icon, the
# window size, where the two icons sit, the backdrop — is metadata, and none
# of it is written here. dmgbuild writes it into the volume's .DS_Store
# directly, from Scripts/dmg-settings.py, which is also where the reasoning
# about each setting lives. check-dmg.sh reads the finished image back.
#
# Signing: with a Developer ID in the keychain, pass its name as $1 and the
# image is signed. Set BILBY_NOTARY_PROFILE as well and it is notarised and
# stapled, which is what makes the first open an ordinary double-click. Store
# the profile once with:
#   xcrun notarytool store-credentials bilby \
#       --apple-id <you> --team-id <team> --password <app-specific password>
# Without a Developer ID the app is ad-hoc signed, which still works — a
# privacy grant sticks to that exact build — but Gatekeeper refuses the first
# open with no visible way forward.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTITY="${1:-}"
NOTARY_PROFILE="${BILBY_NOTARY_PROFILE:-}"
STAGE="$ROOT/.build/dmg"
APP="$STAGE/Bilby.app"
DMG="$ROOT/.build/Bilby.dmg"
ART="$ROOT/.build/dmg-art"
# shellcheck source=Scripts/dmg-tools.sh
. "$ROOT/Scripts/dmg-tools.sh"

rm -rf "$STAGE" "$DMG" "$ART"
# Only $ART: make-app.sh creates the app's parent itself, but Core Graphics
# will not create a directory to write a PNG into.
mkdir -p "$ART"
# Build straight into the staging folder: the image must hold the app that
# was just built, not whatever an earlier run left in .build.
BILBY_CONFIG=release BILBY_APP_PATH="$APP" "$ROOT/Scripts/make-app.sh" >/dev/null
"$ROOT/Scripts/check-app-portable.sh" "$APP"

# No --deep: the bundle holds one Mach-O, Contents/MacOS/Bilby, so there is
# nothing nested to recurse into, and Apple deprecated the flag for signing.
# The ad-hoc case needs no branch — make-app.sh has already ad-hoc signed the
# app, and it does so quietly, so the verify below is what turns a failure
# there into a failed release rather than a warning nobody read.
if [ -n "$IDENTITY" ]; then
    echo "signing with: $IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
    echo "no Developer ID given — ad-hoc signed: on macOS 15 and later the first open is blocked until the user allows it in System Settings → Privacy & Security"
fi
"$ROOT/Scripts/check-app-security.sh" "$APP"

# The 1x and 2x drawings, side by side under the names dmgbuild pairs up.
swift "$ROOT/Scripts/make-dmg-art.swift" \
      "$ART/background.png" "$ART/background@2x.png"

"$DMG_BUILD" -s "$ROOT/Scripts/dmg-settings.py" \
             -D app="$APP" \
             -D volume_icon="$ROOT/Resources/Bilby.icns" \
             -D background="$ART/background.png" \
             Bilby "$DMG" >/dev/null

if [ -n "$IDENTITY" ] && [ -n "$NOTARY_PROFILE" ]; then
    echo "notarising (this waits on Apple, usually a few minutes)…"
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    echo "notarised and stapled"
elif [ -n "$IDENTITY" ]; then
    echo "signed but not notarised — set BILBY_NOTARY_PROFILE to notarise"
fi

"$ROOT/Scripts/check-dmg.sh" "$DMG"
(cd "$ROOT/.build" && shasum -a 256 Bilby.dmg > Bilby.dmg.sha256)
echo "$DMG ($(du -h "$DMG" | cut -f1))"
