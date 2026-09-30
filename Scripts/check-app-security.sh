#!/bin/bash
# A valid ad-hoc signature alone does not prevent library injection.
set -euo pipefail
APP="${1:?usage: check-app-security.sh /path/to/Bilby.app}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

codesign --verify --strict "$APP"
codesign --display --verbose=4 "$APP" >"$WORK/signature.txt" 2>&1
if ! grep -Eq '^CodeDirectory .*flags=.*runtime' "$WORK/signature.txt"; then
    echo "✗ Hardened Runtime is missing: $APP" >&2
    exit 1
fi
codesign --display --entitlements - --xml "$APP" >"$WORK/entitlements.plist" 2>/dev/null
python3 - "$WORK/entitlements.plist" <<'PYTHON'
import pathlib
import plistlib
import sys

data = pathlib.Path(sys.argv[1]).read_bytes()
entitlements = plistlib.loads(data) if data else {}
for key in (
    "com.apple.security.get-task-allow",
    "com.apple.security.cs.allow-dyld-environment-variables",
    "com.apple.security.cs.allow-jit",
    "com.apple.security.cs.disable-library-validation",
    "com.apple.security.cs.allow-unsigned-executable-memory",
    "com.apple.security.cs.disable-executable-page-protection",
):
    if entitlements.get(key):
        raise SystemExit(f"✗ Unsafe runtime entitlement: {key}")
PYTHON
echo "✓ signature and Hardened Runtime verified; no unsafe runtime exceptions"
