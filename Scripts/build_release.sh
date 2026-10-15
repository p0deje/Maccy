#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEYCHAIN="${MACCY_KEYCHAIN:?Configure the runner signing Keychain}"
PASSWORD_FILE="${MACCY_KEYCHAIN_PASSWORD_FILE:?Configure the local Keychain password file}"
NOTARY_PROFILE="${MACCY_NOTARY_PROFILE:?Configure the local notarization profile}"
BUILD_NUMBER="${BUILD_NUMBER:?Set a monotonically increasing build number}"
BUILD_DIR="$ROOT_DIR/Build"
DERIVED_DATA="$ROOT_DIR/.release/DerivedData"
APP_PATH="$BUILD_DIR/Maccy.app"
ZIP_PATH="$BUILD_DIR/Maccy.zip"

[[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]
[[ -f "$KEYCHAIN" && ! -L "$KEYCHAIN" ]]
[[ -f "$PASSWORD_FILE" && ! -L "$PASSWORD_FILE" ]]
security unlock-keychain -p "$(<"$PASSWORD_FILE")" "$KEYCHAIN"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --keychain "$KEYCHAIN" >/dev/null
IDENTITY="$(security find-identity -v -p codesigning "$KEYCHAIN" | awk '/Developer ID Application:/ {print $2; exit}')"
[[ -n "$IDENTITY" ]] || { echo "No local Developer ID signing identity is available." >&2; exit 1; }

mkdir -p "$BUILD_DIR" "$ROOT_DIR/.release"
touch "$BUILD_DIR/.metadata_never_index" "$ROOT_DIR/.release/.metadata_never_index"
cleanup_registration() {
    for app in "$APP_PATH" "$DERIVED_DATA/Build/Products/Release/Maccy.app"; do
        /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
            -u "$app" >/dev/null 2>&1 || true
    done
}
trap cleanup_registration EXIT

xcodebuild -quiet -project "$ROOT_DIR/Maccy.xcodeproj" -scheme Maccy \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" build

rm -rf "$APP_PATH"
ditto "$DERIVED_DATA/Build/Products/Release/Maccy.app" "$APP_PATH"
python3 - "$ROOT_DIR" "$APP_PATH" <<'PY'
import pathlib, plistlib, sys
root, app = map(pathlib.Path, sys.argv[1:])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
source = (root / 'Maccy/Maccy.entitlements').read_text()
source = source.replace('$(PRODUCT_BUNDLE_IDENTIFIER)', info['CFBundleIdentifier'])
(root / '.release/Maccy.entitlements').write_text(source)
PY

SPARKLE="$APP_PATH/Contents/Frameworks/Sparkle.framework"
for nested in \
    "$SPARKLE/Versions/Current/XPCServices/Downloader.xpc" \
    "$SPARKLE/Versions/Current/XPCServices/Installer.xpc" \
    "$SPARKLE/Versions/Current/Autoupdate" \
    "$SPARKLE/Versions/Current/Updater.app" \
    "$SPARKLE"; do
    codesign --force --keychain "$KEYCHAIN" --sign "$IDENTITY" \
        --options runtime --timestamp --preserve-metadata=entitlements "$nested"
done
codesign --force --keychain "$KEYCHAIN" --sign "$IDENTITY" --options runtime --timestamp \
    --entitlements "$ROOT_DIR/.release/Maccy.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
for arch in arm64 x86_64; do
    lipo "$APP_PATH/Contents/MacOS/Maccy" -verify_arch "$arch"
done

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" \
    --keychain "$KEYCHAIN" --wait --output-format json > "$BUILD_DIR/notary-result.json"
[[ "$(plutil -extract status raw -o - "$BUILD_DIR/notary-result.json")" == Accepted ]]
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute "$APP_PATH"
rm "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
(cd "$BUILD_DIR" && shasum -a 256 Maccy.zip > Maccy.zip.sha256)
echo "Maccy release is signed, notarized, and stapled for arm64 and x86_64."
