#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$HOME/Applications/Clocktower.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
APP_SUPPORT_DIR="$HOME/Library/Application Support/Clocktower"
BUNDLE_ID="com.clocktower.app"
LAUNCH_AGENT_DEST="$HOME/Library/LaunchAgents/$BUNDLE_ID.plist"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
ICONSET_DIR="$ROOT_DIR/.build/Clocktower.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"
INSTALL_LOG="$APP_SUPPORT_DIR/install.log"

mkdir -p "$APP_SUPPORT_DIR"
exec > >(tee -a "$INSTALL_LOG") 2>&1

timestamp() {
    /bin/date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
    echo "$(timestamp) $*"
}

log "install start root=$ROOT_DIR app=$APP_DIR"
swift build -c release
rm -rf "$ICONSET_DIR" "$ROOT_DIR/.build/AppIcon.icns"
/usr/bin/swift "$ROOT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$ROOT_DIR/.build/AppIcon.icns"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BUILD_DIR/Clocktower" "$MACOS_DIR/Clocktower"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/.build/AppIcon.icns" "$ICON_PATH"
mkdir -p "$LAUNCH_AGENTS_DIR"

for plist in "$LAUNCH_AGENTS_DIR"/*.plist(N); do
    [[ -f "$plist" ]] || continue

    if /usr/bin/plutil -extract ProgramArguments raw -o - "$plist" 2>/dev/null | /usr/bin/grep -qi "Clocktower.app"; then
        log "removing stale launch agent $plist"
        launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
        rm -f "$plist"
    fi
done

cat > "$LAUNCH_AGENT_DEST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$BUNDLE_ID</string>
    <key>ProgramArguments</key>
    <array>
        <string>$APP_DIR/Contents/MacOS/Clocktower</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP_DIR"
"$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true

log "killing stale Clocktower processes"
/usr/bin/pkill -if '/Clocktower.app/Contents/MacOS/Clocktower|Clocktower.app' >/dev/null 2>&1 || true
sleep 1

log "reloading launch agent $LAUNCH_AGENT_DEST"
launchctl bootout "gui/$(id -u)" "$LAUNCH_AGENT_DEST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_DEST"
launchctl kickstart -k "gui/$(id -u)/$BUNDLE_ID" >/dev/null 2>&1 || true

log "install complete app=$APP_DIR"
echo "Installed Clocktower to $APP_DIR"
echo "Logs: $APP_SUPPORT_DIR/clocktower.log and $INSTALL_LOG"
echo "If macOS prompts for notifications, allow them for Clocktower."
