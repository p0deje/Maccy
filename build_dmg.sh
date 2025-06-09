#!/bin/bash

# Setups
set -e
APP_NAME="Maccy"
ARCHIVE_PATH="build/${APP_NAME}.xcarchive"
EXPORT_PATH="build/exported"

# Check for create-dmg
if ! [ -x "$(command -v create-dmg)" ]; then
  echo 'Error: create-dmg is not installed. Please install it by running "brew install create-dmg"' >&2
  exit 1
fi

echo "Building and creating DMG for ${APP_NAME}"

# Clean up previous build
echo "Cleaning up..."
rm -rf build/
rm -rf dist/
mkdir -p build
mkdir -p dist

# Archive
echo "Archiving..."
xcodebuild -project "${APP_NAME}.xcodeproj" \
           -scheme "${APP_NAME}" \
           -configuration Release \
           -archivePath "${ARCHIVE_PATH}" \
           archive

# Get version and build number from archived Info.plist
INFO_PLIST_PATH="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app/Contents/Info.plist"
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "${INFO_PLIST_PATH}")
APP_BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "${INFO_PLIST_PATH}")

VOLUME_NAME="${APP_NAME} ${APP_VERSION}"
DMG_NAME="${APP_NAME}-${APP_VERSION}.dmg"
APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"

echo "Building and creating DMG for ${APP_NAME} version ${APP_VERSION} (build ${APP_BUILD})"

# Export
echo "Exporting..."
xcodebuild -exportArchive \
           -archivePath "${ARCHIVE_PATH}" \
           -exportPath "${EXPORT_PATH}" \
           -exportOptionsPlist "Maccy/exportOptions.plist"

# Check if app exists
if [ ! -d "${APP_PATH}" ]; then
    echo "Error: ${APP_PATH} does not exist."
    exit 1
fi

# Create DMG
echo "Creating DMG..."
create-dmg \
  --volname "${VOLUME_NAME}" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 200 190 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 600 185 \
  "dist/${DMG_NAME}" \
  "${APP_PATH}"

echo "DMG created at dist/${DMG_NAME}" 