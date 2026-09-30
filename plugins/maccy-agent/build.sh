#!/usr/bin/env bash
#
# build.sh — build and package maccy-agent (the lightweight clipboard
# companion).
#
# Modes:
#   ./build.sh             build → .build/release/maccy-agent
#   ./build.sh --package   … and zip [binary, install.sh, README.md] into
#                          build/maccy-agent-<version>.zip via ditto + sha256
#                          (the distribution artifact for secondsee.com)
#
# Flags combine when the second arg carries one (./build.sh build --package).
#
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-build}"
MODE2="${2:-}"

swift build -c release
echo "✓ built: $(pwd)/.build/release/maccy-agent"

if [[ "$MODE" == "--package" || "$MODE2" == "--package" ]]; then
  VERSION=$(grep -o 'let maccyAgentVersion = "[^"]*"' Sources/maccy-agent/History.swift | sed 's/.*"\(.*\)"/\1/')
  STAGE="build/package/maccy-agent-$VERSION"
  mkdir -p "$STAGE"
  cp .build/release/maccy-agent install.sh README.md "$STAGE/"
  # zip -X: no AppleDouble ._ files / extended attributes in the artifact.
  (cd build/package && zip -X -r -q "maccy-agent-$VERSION.zip" "maccy-agent-$VERSION")
  SHA=$(shasum -a 256 "build/package/maccy-agent-$VERSION.zip" | awk '{print $1}')
  echo "✓ packaged → build/package/maccy-agent-$VERSION.zip ($SHA)"
  echo "  contains: maccy-agent (binary), install.sh (installs it directly), README.md"
fi