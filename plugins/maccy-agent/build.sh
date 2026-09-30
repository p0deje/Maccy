#!/usr/bin/env bash
#
# build.sh — build maccy-agent (the lightweight clipboard companion).
#
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
echo "✓ built: $(pwd)/.build/release/maccy-agent"