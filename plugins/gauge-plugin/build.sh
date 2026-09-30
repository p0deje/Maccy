#!/usr/bin/env bash
#
# build.sh — build, sign, and package the Gauge Maccy plugin as
# GaugeMaccyPlugin.gaugeplugin.
#
# Modes:
#   ./build.sh             build + sign into build/Build/Products/Release/
#   ./build.sh --install   … and copy into ~/Library/Application Support/Gauge/Plugins
#                          (Gauge must be RELAUNCHED — plugins load at launch)
#   ./build.sh --package   … and zip the plugin into build/ via ditto
#
# Mirror of com.sqeakd.macos/plugins/gauge-plugin/build.sh (the verified
# squeakd lane). Flags combine when the second arg carries one.
#
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=${CONFIG:-Release}
PLUGIN_NAME=GaugeMaccyPlugin
MODE="${1:-build}"
MODE2="${2:-}"

# --- Toolchain checks -------------------------------------------------------
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "▸ xcodegen missing — attempting 'brew install xcodegen'"
  if command -v brew >/dev/null 2>&1; then
    brew install xcodegen
  else
    echo "ERROR: xcodegen not found and Homebrew unavailable." >&2
    echo "Install it (brew install xcodegen) or hand-write ${PLUGIN_NAME}.xcodeproj:" >&2
    echo "  target ${PLUGIN_NAME}, type bundle, macOS 13.0, sources Sources/," >&2
    echo "  INFOPLIST_FILE=Info.plist, PRODUCT_BUNDLE_EXTENSION=gaugeplugin," >&2
    echo "  GENERATE_INFOPLIST_FILE=NO, ENABLE_HARDENED_RUNTIME=YES, SKIP_INSTALL=YES." >&2
    exit 1
  fi
fi
command -v xcodebuild >/dev/null 2>&1 || { echo "ERROR: xcodebuild not found" >&2; exit 1; }

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# --- Build identity stamp (mirrors squeakd/reflex build scripts) ------------
# CFBundleVersion = monotonic commit count so a stale installed plugin is
# detectable without launching anything.
BUILD_NUM=$(git rev-list --count HEAD 2>/dev/null || echo 1)
echo "▸ build identity: CFBundleVersion=$BUILD_NUM"

echo "▸ xcodegen generate"
xcodegen generate >/dev/null

echo "▸ xcodebuild ($CONFIG, unsigned)"
xcodebuild -project "${PLUGIN_NAME}.xcodeproj" -scheme "$PLUGIN_NAME" \
  -configuration "$CONFIG" -destination 'platform=macOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CURRENT_PROJECT_VERSION="$BUILD_NUM" build >/tmp/gmp-build.log 2>&1 \
  || { tail -40 /tmp/gmp-build.log; exit 1; }

BUNDLE="build/Build/Products/$CONFIG/${PLUGIN_NAME}.bundle"
DEST="build/Build/Products/$CONFIG/${PLUGIN_NAME}.gaugeplugin"

# --- Sign --------------------------------------------------------------------
# Prefer a real "Developer ID Application" identity (team 42R8ZPM5N8 when
# present). Gauge ships disable-library-validation, so a Developer-ID plugin
# loads without re-signing the host. Without one, fall back to ad-hoc (no
# hardened-runtime flag — that pairing is rejected for ad-hoc signatures).
IDENTITY=${SIGN_IDENTITY:-}
if [[ -z "$IDENTITY" ]]; then
  IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $1}' | awk '{print $2}' | head -1 || true)
fi
if [[ -n "${IDENTITY:-}" ]]; then
  echo "▸ codesign (Developer ID Application, hardened runtime)"
  codesign --force --sign "$IDENTITY" --options runtime "$BUNDLE"
else
  if [[ "${REQUIRE_DEVELOPER_ID:-0}" == "1" ]]; then
    echo "✗ No Developer ID Application identity — required (REQUIRE_DEVELOPER_ID=1)." >&2
    exit 1
  fi
  echo "▸ codesign (ad-hoc — no Developer ID Application identity available; NOT catalog-shippable)"
  codesign --force --deep -s - "$BUNDLE"
fi

# Xcode emits .bundle; Gauge discovers *.gaugeplugin, so rename the signed bundle.
rm -rf "$DEST"
mv "$BUNDLE" "$DEST"
codesign --verify --strict "$DEST" && echo "✓ signed plugin: $DEST"

# --- Install ------------------------------------------------------------------
if [[ "$MODE" == "--install" || "$MODE2" == "--install" ]]; then
  PLUGINS_DIR="$HOME/Library/Application Support/Gauge/Plugins"
  mkdir -p "$PLUGINS_DIR"
  rm -rf "$PLUGINS_DIR/${PLUGIN_NAME}.gaugeplugin"
  cp -R "$DEST" "$PLUGINS_DIR/"
  echo "✓ installed to $PLUGINS_DIR (relaunch Gauge to load it)"
fi

# --- Package ------------------------------------------------------------------
if [[ "$MODE" == "--package" || "$MODE2" == "--package" ]]; then
  STAGE="${STAGE_DIR:-build}"
  mkdir -p "$STAGE"
  ditto -c -k --keepParent "$DEST" "$STAGE/${PLUGIN_NAME}.gaugeplugin.zip"
  SHA=$(shasum -a 256 "$STAGE/${PLUGIN_NAME}.gaugeplugin.zip" | awk '{print $1}')
  echo "✓ packaged → $STAGE/${PLUGIN_NAME}.gaugeplugin.zip  sha256=$SHA"
fi