#!/bin/bash
# Remove aerox-buttons.
set -uo pipefail

BUNDLE_ID="com.roberto.aerox-buttons"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"

launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null
rm -f "$AGENT"
pkill -f "AeroxButtons.app/Contents/MacOS/aerox-buttons" 2>/dev/null
rm -rf "$HOME/.aerox-buttons"
rm -f /tmp/aerox-buttons.log /tmp/aerox-buttons.err

echo "aerox-buttons removed."
echo "The TCC entry remains in System Settings > Privacy & Security > Input Monitoring;"
echo "remove it there if you want a clean slate."
