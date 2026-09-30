#!/usr/bin/env bash
#
# install.sh — build maccy-agent and register it as a LaunchAgent so it
# captures clipboard history even while Gauge is closed.
#
#   ./install.sh            build + install LaunchAgent + start it
#   ./install.sh uninstall  stop + remove the LaunchAgent (binary stays)
#
set -euo pipefail
cd "$(dirname "$0")"

LABEL="com.ebowwa.maccy.agent"
APP_SUPPORT="$HOME/Library/Application Support/maccy-agent"
BIN_DEST="$APP_SUPPORT/maccy-agent"
HISTORY="$APP_SUPPORT/history.json"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$APP_SUPPORT/maccy-agent.log"
DOMAIN="gui/$(id -u)/$LABEL"

if [[ "${1:-}" == "uninstall" ]]; then
  launchctl bootout "$DOMAIN" 2>/dev/null || true
  rm -f "$PLIST"
  echo "✓ stopped and removed LaunchAgent $LABEL (binary + history kept in $APP_SUPPORT)"
  exit 0
fi

./build.sh

mkdir -p "$APP_SUPPORT"
cp "$(pwd)/.build/release/maccy-agent" "$BIN_DEST"
chmod +x "$BIN_DEST"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN_DEST</string>
        <string>--history-path</string>
        <string>$HISTORY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
PLIST

launchctl bootout "$DOMAIN" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "$DOMAIN"
launchctl kickstart -k "$DOMAIN" 2>/dev/null || true

echo "✓ maccy-agent installed as LaunchAgent $LABEL"
echo "  binary:  $BIN_DEST"
echo "  history: $HISTORY"
echo "  log:     $LOG"
echo "  uninstall: ./install.sh uninstall"