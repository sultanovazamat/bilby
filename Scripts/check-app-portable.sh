#!/bin/bash
# The built app must not depend on this checkout. SwiftPM's resource accessor
# falls back to the absolute build path, which once hid a launch crash on
# every Mac but the one that built it. Run the app with this directory
# unreadable and require it to stay alive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/Bilby.app}"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"

# One directory per run, outside the checkout, removed on the way out.
#
# The app is told where to log with $BILBY_LOG_PATH rather than being read at
# its default path, which every Bilby on the machine shares. Reading the shared
# one made this check wrong in both directions: a copy already running from
# ~/Applications would satisfy the grep below on behalf of the app under test,
# and that copy truncating the log on its own launch would delete the line this
# check is waiting for.
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
OUTPUT="$WORK/stderr.txt"
APPLOG="$WORK/bilby.log"

# Checked before the app runs: a missing bundle is a packaging mistake, and
# saying so beats waiting ten seconds to say the app never loaded it.
BUNDLE="$APP/Contents/Resources/Bilby_BilbyUI.bundle"
for file in menu-bar.png menu-sources.png; do
    [ -f "$BUNDLE/$file" ] || { echo "✗ $BUNDLE/$file is missing"; exit 1; }
done

# The app itself may live inside the checkout (release.sh stages it under
# .build), so its own path is allowed back in; the last matching rule wins.
BILBY_LOG_PATH="$APPLOG" \
sandbox-exec -p "(version 1)(allow default)(deny file-read* (subpath \"$ROOT\"))(allow file-read* (subpath \"$APP\"))" \
    "$APP/Contents/MacOS/Bilby" >"$OUTPUT" 2>&1 &
PID=$!

# Waits for the line rather than sleeping a fixed six seconds, which was both
# slower than it needed to be and a race in both directions. The two-second
# floor is deliberate: an app that loads its resources and then crashes has
# still crashed, so the line alone is not enough to stop watching.
for step in $(seq 100); do
    kill -0 "$PID" 2>/dev/null || break
    [ "$step" -ge 20 ] && grep -q "resources: $BUNDLE" "$APPLOG" 2>/dev/null && break
    sleep 0.1
done

if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    wait "$PID" 2>/dev/null || true  # keeps the shell from announcing "Terminated"
else
    echo "✗ $APP died without $ROOT:"
    cat "$OUTPUT"
    exit 1
fi
# Alive is not enough: the resolver answers nil rather than crashing, so an
# app shipped without its images would pass and show empty pages. The app must
# have found the bundle in the shipped layout.
grep -q "resources: $BUNDLE" "$APPLOG" || {
    echo "✗ the app did not load its images from $BUNDLE:"
    grep "resources:" "$APPLOG" || echo "(no resources line in the log)"
    exit 1
}
echo "✓ $APP runs without $ROOT and found its images in Contents/Resources"
