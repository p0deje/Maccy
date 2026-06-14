#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-Maccy.xcodeproj}"
SCHEME="${SCHEME:-Maccy}"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA="${DERIVED_DATA:-$PWD/DerivedData}"
PACKAGE_DIR="${PACKAGE_DIR:-$PWD/package}"
CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"

APP_NAME="${APP_NAME:-$SCHEME.app}"
ZIP_NAME="${ZIP_NAME:-$APP_NAME.zip}"

rm -rf "$DERIVED_DATA" "$PACKAGE_DIR"
mkdir -p "$DERIVED_DATA" "$PACKAGE_DIR"

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
  clean build

PRODUCTS_DIR="$DERIVED_DATA/Build/Products/$CONFIGURATION"
APP_PATH="$PRODUCTS_DIR/$APP_NAME"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app bundle is missing: $APP_PATH" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"

ZIP_PATH="$PACKAGE_DIR/$ZIP_NAME"
pushd "$PRODUCTS_DIR" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$APP_NAME" "$ZIP_PATH"
popd >/dev/null

SHASUM_PATH="$ZIP_PATH.sha256"
pushd "$PACKAGE_DIR" >/dev/null
shasum -a 256 "$ZIP_NAME" | tee "$ZIP_NAME.sha256"
popd >/dev/null

cat <<EOF
Packaged $APP_NAME
Bundle identifier: $BUNDLE_IDENTIFIER
Version: $VERSION
Build: $BUILD
Archive: $ZIP_PATH
Checksum: $SHASUM_PATH
EOF

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "app_path=$APP_PATH"
    echo "zip_path=$ZIP_PATH"
    echo "shasum_path=$SHASUM_PATH"
    echo "version=$VERSION"
    echo "build=$BUILD"
    echo "bundle_identifier=$BUNDLE_IDENTIFIER"
  } >> "$GITHUB_OUTPUT"
fi
