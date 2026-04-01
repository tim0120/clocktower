#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$HOME/Applications/Clocktower.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
BUNDLE_ID="com.clocktower.app"
LAUNCH_AGENT_DEST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
ICONSET_DIR="$ROOT_DIR/.build/Clocktower.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

swift build -c release
rm -rf "$ICONSET_DIR" "$ROOT_DIR/.build/AppIcon.icns"
/usr/bin/swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/.build/AppIcon.icns"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/Clocktower" "$MACOS_DIR/Clocktower"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/.build/AppIcon.icns" "$ICON_PATH"
cat > "$LAUNCH_AGENT_DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-gj</string>
        <string>$APP_DIR</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP_DIR"
"$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true

launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_DEST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_DEST"
pkill -f "$APP_DIR/Contents/MacOS/Clocktower" >/dev/null 2>&1 || true
sleep 1
open "$APP_DIR" >/dev/null 2>&1 || true

echo "Installed Clocktower to $APP_DIR"
echo "If macOS prompts for notifications, allow them for Clocktower."
