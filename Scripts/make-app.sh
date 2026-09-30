#!/bin/bash
# A SwiftUI executable without a bundle is treated as a background process:
# no window appears and the system presents no dialogs. Wrap it in a real .app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Not inside ~/Desktop: an app that lives there triggers a Desktop-access
# prompt merely by reading its own resource bundle, and a captions app asking
# to see your files looks exactly as alarming as it sounds.
APP="${BILBY_APP_PATH:-$HOME/Applications/Bilby.app}"
# debug while developing; release.sh asks for release.
CONFIG="${BILBY_CONFIG:-debug}"
# release.yml sets both from the tag and the run; a local build is 0.1.0 (1).
VERSION="${BILBY_VERSION:-0.1.0}"
BUILD_NUMBER="${BILBY_BUILD:-1}"
BUILD="$ROOT/.build/$CONFIG"
mkdir -p "$(dirname "$APP")"

swift build -c "$CONFIG" --product Bilby --package-path "$ROOT" >/dev/null
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/Bilby" "$APP/Contents/MacOS/Bilby"
cp "$ROOT/Resources/Bilby.icns" "$APP/Contents/Resources/Bilby.icns"
# FluidAudio is Apache-2.0 and compiled into the binary, so its licence has to
# travel with every copy of the app, not only with the source.
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

# SwiftPM emits resources as bundles beside the executable. Contents/Resources
# is the only place a signed app may keep them, and UIResources looks there.
# SwiftPM's own Bundle.module would not: it checks the app's top level and then
# the absolute build path of this checkout — which is why the app used to run
# here and crash on every other Mac. check-app-portable.sh guards against that.
for bundle in "$BUILD"/*.bundle; do
    [ -e "$bundle" ] || continue
    case "$bundle" in *CLI.bundle) continue ;; esac  # FluidAudio's tool, not linked
    cp -R "$bundle" "$APP/Contents/Resources/"
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Bilby</string>
  <key>CFBundleIconFile</key><string>Bilby</string>
  <key>CFBundleIdentifier</key><string>io.github.sultanovazamat.bilby</string>
  <key>CFBundleName</key><string>Bilby</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Bilby reads what your meeting app is playing so it can caption and translate it. Nothing leaves this Mac, and your microphone is never used.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Screenshots taken with the Screenshot app carry Finder metadata as extended
# attributes, and codesign refuses a bundle that contains any ("resource
# fork, Finder information, or similar detritus not allowed").
xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed for $APP" >&2
echo "$APP"
