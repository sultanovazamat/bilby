#!/bin/bash
# BilbyCore must stay pure Swift: no audio, no ML, no platform frameworks.
# That is what lets the whole product be tested without a meeting running.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="$ROOT/Sources/BilbyCore"
FORBIDDEN='^import (Speech|Translation|AVFoundation|FoundationModels|CoreAudio|AppKit|SwiftUI)'
# grep answers 0 for "found", 1 for "clean" and 2 for "I could not look".
# Only 1 is a pass: this gate used to take an unreadable directory — which is
# what it saw whenever it was run from anywhere but the repo root — as proof
# of purity, and printed a tick.
grep -rEn "$FORBIDDEN" "$CORE"
case $? in
    0) echo "✗ BilbyCore imports a framework it must not depend on."; exit 1 ;;
    1) echo "✓ BilbyCore is pure." ;;
    *) echo "✗ could not read $CORE"; exit 1 ;;
esac
