#!/bin/bash
# Install aerox-buttons as a login item.
# No sudo needed: everything lives in the user's home directory.
set -euo pipefail

INSTALL_DIR="$HOME/.aerox-buttons"
APP="$INSTALL_DIR/AeroxButtons.app"
BUNDLE_ID="com.roberto.aerox-buttons"
AGENT="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

info() { printf '  %s\n' "$*"; }

echo "aerox-buttons installer"
echo

# 1. Compile
# The ad-hoc signature's cdhash is what macOS stores in TCC, and a rebuild
# changes it (builds are not bit-reproducible). So rebuild only when the source
# is actually newer, otherwise every install would silently revoke the
# Input Monitoring grant.
echo "1/4 Compiling"
mkdir -p "$INSTALL_DIR"
SRC="$SRC_DIR/src/aerox-buttons.c"
BIN="$INSTALL_DIR/aerox-buttons"
if [ -x "$BIN" ] && [ "$BIN" -nt "$SRC" ]; then
    info "binary is up to date, keeping it (preserves the TCC grant)"
else
    clang -O2 -o "$BIN" "$SRC" \
        -framework IOKit -framework CoreFoundation -framework ApplicationServices
    info "built $BIN (rebuilt: if you had already granted Input Monitoring,"
    info " you must re-enable it - the signature changed)"
fi

# 2. Bundle + ad-hoc signature.
# launchd refuses to give Input Monitoring to a bare binary, but a signed .app
# gets its own TCC identity and works.
echo "2/4 Creating app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>aerox-buttons</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>Aerox Buttons</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSBackgroundOnly</key><true/>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
cp "$INSTALL_DIR/aerox-buttons" "$APP/Contents/MacOS/aerox-buttons"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP" 2>/dev/null
info "signed $APP"

# 3. Login item
# Exec the bundle binary directly (not via `open`): that way launchd owns the
# process, can report its state, and restarts it if it dies.
echo "3/4 Installing login item"
mkdir -p "$HOME/Library/LaunchAgents"
launchctl bootout "gui/$(id -u)/$BUNDLE_ID" 2>/dev/null || true
cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP/Contents/MacOS/aerox-buttons</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict><key>SuccessfulExit</key><false/></dict>
    <key>ThrottleInterval</key><integer>10</integer>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>StandardErrorPath</key><string>/tmp/aerox-buttons.err</string>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"
info "registered $AGENT (starts at login, restarts on crash)"

# 4. Input Monitoring
echo "4/4 Checking Input Monitoring"
sleep 3

TCC_DB="/Library/Application Support/com.apple.TCC/TCC.db"
state="$(sqlite3 "$TCC_DB" \
    "select auth_value from access where service='kTCCServiceListenEvent' and client='$BUNDLE_ID';" 2>/dev/null || true)"

if grep -q "started OK" /tmp/aerox-buttons.log 2>/dev/null; then
    echo
    echo "Done. The daemon is running."
    echo "  Log: /tmp/aerox-buttons.log"
    echo "  Press your buttons - each press logs a line."
    exit 0
fi

cat <<'NOTE'

The daemon is installed but macOS is blocking HID access.

  Open:  System Settings > Privacy & Security > Input Monitoring
  Enable "Aerox Buttons"

  A dialog may already be on screen asking for it - click Allow.

Then restart the agent:

  launchctl unload ~/Library/LaunchAgents/com.roberto.aerox-buttons.plist
  launchctl load   ~/Library/LaunchAgents/com.roberto.aerox-buttons.plist

Verify with:

  cat /tmp/aerox-buttons.log      # expect: started OK

NOTE
echo "Current permission state: ${state:-not registered}  (2 = granted, 0 = denied)"
