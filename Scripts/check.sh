#!/bin/bash
# Everything that must be green before a build is handed to anyone.
#
# The release build is here because it is not the debug build: strict
# concurrency checking finds races under whole-module optimisation that the
# debug build accepts, and one of those sat in the tree unnoticed because
# nothing ran it between disk images.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "── tests"
swift test 2>&1 | tail -1
echo "── core purity"
./Scripts/check-core-purity.sh
echo "── release build"
swift build -c release --product Bilby >/dev/null
echo "✓ release builds"
echo "── app, and it runs without this checkout"
./Scripts/make-app.sh >/dev/null
./Scripts/check-app-portable.sh
