# Clocktower

A lightweight macOS menu bar app that chimes at regular intervals to help with time awareness. Swift 6, SwiftPM, no Xcode project.

## Build & Run

```bash
swift build          # debug build
zsh install.sh       # release build + install to ~/Applications + relaunch via launchd
```

`install.sh` is the canonical way to deploy changes — it builds release, copies into the app bundle, codesigns, and restarts the launch agent. Always use `zsh` (not `bash`) as it uses zsh glob qualifiers.

The bare binary cannot run standalone — it requires the app bundle structure for `UNUserNotificationCenter`.

## Project Structure

- `Sources/` — all Swift source, flat (no subdirectories)
  - `main.swift` — entry point
  - `BellApp.swift` — core logic: scheduling, notifications, away detection
  - `BellConfig.swift` — configuration model
  - `ConfigStore.swift` — persistence (UserDefaults)
  - `PreferencesWindowController.swift` — settings UI
  - `AppLogger.swift` — async file logging
  - `ProcessSingleton.swift` — single-instance enforcement

## Key Concepts

- **Notifications** are scheduled via `UNUserNotificationCenter` at fixed intervals
- **Away detection** uses screen lock/sleep system notifications; on return, a catch-up summary is shown
- **Config** lives in UserDefaults under the app's bundle ID (`com.clocktower.app`)

## Notification Examples

- Regular reminder: `It's 2:30 pm.`
- Away catch-up: `Away 1h 23m (9:07 am – 10:30 am)`
- Test notification: `It's 2:30 pm. [test]`

## Logs

- App log: `~/Library/Application Support/Clocktower/clocktower.log`
- Install log: `~/Library/Application Support/Clocktower/install.log`
