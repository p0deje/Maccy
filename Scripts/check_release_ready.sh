#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/Build/Maccy.app"
codesign --verify --deep --strict "$APP_PATH"
codesign -dv "$APP_PATH" 2>&1 | grep -q '^Authority=Developer ID Application:'
if codesign -d --entitlements :- "$APP_PATH" 2>/dev/null | grep -q get-task-allow; then
    echo "The release contains a debug entitlement." >&2
    exit 1
fi
for arch in arm64 x86_64; do
    lipo "$APP_PATH/Contents/MacOS/Maccy" -verify_arch "$arch"
done
xcrun stapler validate "$APP_PATH" >/dev/null
spctl --assess --type execute "$APP_PATH"
[[ "$(plutil -extract SUFeedURL raw -o - "$APP_PATH/Contents/Info.plist")" == \
    https://github.com/iTvX/Maccy/releases/download/appcast/appcast.xml ]]
(cd "$ROOT_DIR/Build" && shasum -a 256 -c Maccy.zip.sha256)
VERIFY_DIR="$(mktemp -d)"
trap 'rm -rf "$VERIFY_DIR"' EXIT
ditto -x -k "$ROOT_DIR/Build/Maccy.zip" "$VERIFY_DIR"
codesign --verify --deep --strict "$VERIFY_DIR/Maccy.app"
xcrun stapler validate "$VERIFY_DIR/Maccy.app" >/dev/null
echo "Release readiness checks passed."
