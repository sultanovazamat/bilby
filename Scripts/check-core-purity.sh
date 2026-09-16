#!/bin/bash
# BilbyCore must stay pure Swift: no audio, no ML, no platform frameworks.
# That is what lets the whole product be tested without a meeting running.
set -u
FORBIDDEN='^import (Speech|Translation|AVFoundation|FoundationModels|CoreAudio|AppKit|SwiftUI)'
if grep -rEn "$FORBIDDEN" Sources/BilbyCore; then
    echo "✗ BilbyCore imports a framework it must not depend on."
    exit 1
fi
echo "✓ BilbyCore is pure."
