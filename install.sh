#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$HOME/Applications/Clocktower.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"
APP_SUPPORT_DIR="$HOME/Library/Application Support/Clocktower"
BUNDLE_ID="com.tim0120.clocktower"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
ICONSET_DIR="$ROOT_DIR/.build/Clocktower.iconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"
INSTALL_LOG="$APP_SUPPORT_DIR/install.log"
PLUGINS_DIR="$APP_DIR/Contents/PlugIns"
CONTROL_EXTENSION_NAME="ClocktowerControls"
CONTROL_EXTENSION_DIR="$ROOT_DIR/Extensions/ClocktowerControls"
CONTROL_APPEX_DIR="$PLUGINS_DIR/$CONTROL_EXTENSION_NAME.appex"
CONTROL_APPEX_MACOS_DIR="$CONTROL_APPEX_DIR/Contents/MacOS"

mkdir -p "$APP_SUPPORT_DIR"
exec > >(tee -a "$INSTALL_LOG") 2>&1

timestamp() {
    /bin/date -u +"%Y-%m-%dT%H:%M:%SZ"
}

log() {
    echo "$(timestamp) $*"
}

build_controls_extension() {
    local product_version major arch target

    product_version="$(/usr/bin/sw_vers -productVersion)"
    major="${product_version%%.*}"
    if [[ "$major" != <-> ]] || (( major < 26 )); then
        log "skipping Control Center extension: macOS $product_version is older than 26.0"
        rm -rf "$CONTROL_APPEX_DIR"
        return
    fi

    arch="$(/usr/bin/uname -m)"
    target="${arch}-apple-macosx26.0"

    log "building Control Center extension target=$target"
    rm -rf "$CONTROL_APPEX_DIR"
    mkdir -p "$CONTROL_APPEX_MACOS_DIR"
    # App extensions enter through Foundation's NSExtensionMain (which handles
    # the XPC host check-in), not the Swift-generated main — same as Xcode.
    /usr/bin/swiftc \
        -target "$target" \
        -O \
        -parse-as-library \
        -application-extension \
        -Xlinker -e -Xlinker _NSExtensionMain \
        -framework Foundation \
        "$CONTROL_EXTENSION_DIR/ClocktowerControls.swift" \
        "$ROOT_DIR/Sources/BellConfig.swift" \
        "$ROOT_DIR/Sources/ConfigStore.swift" \
        "$ROOT_DIR/Sources/ClocktowerShared.swift" \
        -o "$CONTROL_APPEX_MACOS_DIR/$CONTROL_EXTENSION_NAME"
    cp "$CONTROL_EXTENSION_DIR/Info.plist" "$CONTROL_APPEX_DIR/Contents/Info.plist"
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
build_controls_extension
for plist in "$LAUNCH_AGENTS_DIR"/*.plist(N); do
    [[ -f "$plist" ]] || continue

    if /usr/bin/plutil -p "$plist" 2>/dev/null | /usr/bin/grep -qi "Clocktower.app"; then
        log "removing stale launch agent $plist"
        launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
        rm -f "$plist"
    fi
done
# Sign the extension first (with its sandbox/app-group entitlements), then the
# app without --deep so the extension's entitlements survive.
if [[ -d "$CONTROL_APPEX_DIR" ]]; then
    codesign --force --sign - --entitlements "$CONTROL_EXTENSION_DIR/ClocktowerControls.entitlements" "$CONTROL_APPEX_DIR"
fi
codesign --force --sign - --entitlements "$ROOT_DIR/Clocktower.entitlements" "$APP_DIR"
"$LSREGISTER" -f "$APP_DIR" >/dev/null 2>&1 || true
if [[ -d "$CONTROL_APPEX_DIR" ]]; then
    log "registering Control Center extension $CONTROL_APPEX_DIR"
    /usr/bin/pluginkit -a "$CONTROL_APPEX_DIR" >/dev/null 2>&1 || true
fi

log "killing stale Clocktower processes"
/usr/bin/pkill -if '/Clocktower.app/Contents/MacOS/Clocktower|Clocktower.app' >/dev/null 2>&1 || true
sleep 1

# Only touch login items when ours is missing, so reinstalls don't fire
# repeated background-item events.
if /usr/bin/osascript -e 'tell application "System Events" to get the path of every login item' 2>/dev/null | /usr/bin/grep -q "Clocktower.app"; then
    log "login item already registered"
else
    log "registering login item $APP_DIR"
    /usr/bin/osascript <<APPLESCRIPT
tell application "System Events"
    make login item at end with properties {name:"Clocktower", path:"$APP_DIR", hidden:false}
end tell
APPLESCRIPT
fi
/usr/bin/open "$APP_DIR"

log "install complete app=$APP_DIR"
echo "Installed Clocktower to $APP_DIR"
echo "Logs: $APP_SUPPORT_DIR/clocktower.log and $INSTALL_LOG"
echo "If macOS prompts for notifications, allow them for Clocktower."
