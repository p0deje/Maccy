#!/bin/bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_TAG="${RELEASE_TAG:?Set the release tag}"
REPOSITORY="${GITHUB_REPOSITORY:?Set the release repository}"
ACCOUNT="${MACCY_SPARKLE_ACCOUNT:?Configure the local Sparkle signing account}"
BIN="${MACCY_SPARKLE_BIN_DIR:-$ROOT_DIR/.release/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}"
STAGE="$ROOT_DIR/Build/Appcast"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$ROOT_DIR/Build/Maccy.zip" "$STAGE/Maccy.zip"
curl -fsSL "https://github.com/$REPOSITORY/releases/download/appcast/appcast.xml" \
    -o "$STAGE/appcast.xml" 2>/dev/null || true
"$BIN/generate_appcast" --account "$ACCOUNT" --maximum-versions 3 --maximum-deltas 0 \
    --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$RELEASE_TAG/" \
    --link "https://github.com/$REPOSITORY" "$STAGE" >/dev/null
signature="$(python3 - "$STAGE/appcast.xml" "$RELEASE_TAG" <<'PY'
import sys, xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
for item in root.findall('./channel/item/enclosure'):
    if '/releases/download/' + sys.argv[2] + '/Maccy.zip' in item.attrib.get('url', ''):
        print(item.attrib['{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'])
        break
else:
    raise SystemExit('The generated feed is missing this release.')
PY
)"
"$BIN/sign_update" --account "$ACCOUNT" --verify "$ROOT_DIR/Build/Maccy.zip" "$signature"
echo "Sparkle update signature verified."
