#!/bin/bash
# A SwiftUI executable without a bundle is treated as a background process:
# no window appears and the system presents no dialogs. Wrap it in a real .app.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Not inside ~/Desktop: an app that lives there triggers a Desktop-access
# prompt merely by reading its own resource bundle, and a captions app asking
# to see your files looks exactly as alarming as it sounds. Denying it then
# leaves the app unable to load its own images.
APP="${BILBY_APP_PATH:-$HOME/Applications/Bilby.app}"
mkdir -p "$(dirname "$APP")"

swift build --product Bilby --package-path "$ROOT" >/dev/null
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$ROOT/.build/debug/Bilby" "$APP/Contents/MacOS/Bilby"

# SwiftPM emits resources as separate bundles beside the executable, and
# Bundle.module looks for them there. Copying only the binary produced an app
# whose onboarding screenshots silently did not exist.
mkdir -p "$APP/Contents/Resources"
cp "$ROOT/Resources/Bilby.icns" "$APP/Contents/Resources/Bilby.icns"

# Bundle.module searches Bundle.main.resourceURL — Contents/Resources — before
# anything beside the executable. Copying only to MacOS produced an app whose
# screenshots existed on disk and were invisible to the code looking for them.
for bundle in "$ROOT"/.build/debug/*.bundle; do
    [ -e "$bundle" ] || continue
    cp -R "$bundle" "$APP/Contents/Resources/"
    cp -R "$bundle" "$APP/Contents/MacOS/"
done
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>Bilby</string>
  <key>CFBundleIconFile</key><string>Bilby</string>
  <key>CFBundleIdentifier</key><string>net.variant.bilby</string>
  <key>CFBundleName</key><string>Bilby</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>LSUIElement</key><true/>
  <key>NSAudioCaptureUsageDescription</key><string>Bilby reads what your meeting app is playing so it can caption and translate it. Nothing leaves this Mac, and your microphone is never used.</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
