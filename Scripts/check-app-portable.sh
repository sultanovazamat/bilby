#!/bin/bash
# The built app must not depend on this checkout. SwiftPM's resource accessor
# falls back to the absolute build path, which once hid a launch crash on
# every Mac but the one that built it. Run the app with this directory
# unreadable and require it to stay alive.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$HOME/Applications/Bilby.app}"
APP="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
LOG="$(mktemp)"
# The app itself may live inside the checkout (release.sh stages it under
# .build), so its own path is allowed back in; the last matching rule wins.
sandbox-exec -p "(version 1)(allow default)(deny file-read* (subpath \"$ROOT\"))(allow file-read* (subpath \"$APP\"))" \
    "$APP/Contents/MacOS/Bilby" >"$LOG" 2>&1 &
PID=$!
sleep 6
if kill -0 "$PID" 2>/dev/null; then
    kill "$PID"
    echo "✓ $APP runs without $ROOT"
else
    echo "✗ $APP died without $ROOT:"
    cat "$LOG"
    exit 1
fi
