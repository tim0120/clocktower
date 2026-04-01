# Clocktower

A small native macOS menu bar app that sends timed reminders at regular intervals.

## Features

- Lives in the menu bar — no dock icon, no windows in the way
- Sends local notifications with configurable title, body, sound, and interval
- Defaults to every 30 minutes with a system sound
- Body template supports `{{time}}` to include the current time
- Optional presentation suppression — skip notifications when the frontmost app is Zoom, Teams, Keynote, etc.
- Preferences window accessible from the menu bar
- Installs a LaunchAgent so it starts automatically at login

## Requirements

- macOS 13.0+
- Swift 6.0+ (included with Xcode 16+)

## Install

```bash
git clone https://github.com/tim0120/clocktower.git
cd clocktower
chmod +x install.sh
./install.sh
```

The install script builds the app, creates `~/Applications/Clocktower.app`, generates an app icon, and registers a LaunchAgent to start it at login.

When macOS prompts for notification permissions, allow them for Clocktower.

## Uninstall

```bash
launchctl bootout "gui/$(id -u)" ~/Library/LaunchAgents/com.clocktower.app.plist
rm ~/Library/LaunchAgents/com.clocktower.app.plist
rm -rf ~/Applications/Clocktower.app
rm -rf ~/Library/Application\ Support/Clocktower
```

## Configuration

Configuration is stored at:

```
~/Library/Application Support/Clocktower/config.json
```

You can edit it directly or use the **Preferences** window from the menu bar icon.

Default config:

```json
{
  "bodyTemplate": "It's {{time}}.",
  "intervalMinutes": 30,
  "presentationApps": [
    "Keynote",
    "Microsoft PowerPoint",
    "zoom.us",
    "Microsoft Teams",
    "Google Chrome",
    "Safari"
  ],
  "soundName": "Tink",
  "suppressWhenPresenting": false,
  "title": "Clocktower"
}
```

| Field | Description |
|-------|-------------|
| `intervalMinutes` | Minutes between reminders (minimum 1) |
| `title` | Notification title |
| `bodyTemplate` | Notification body. `{{time}}` is replaced with the current time |
| `soundName` | macOS system sound name, or `null` for default |
| `suppressWhenPresenting` | Skip notifications when a presentation app is the frontmost window |
| `presentationApps` | App names to check when suppression is enabled |

## Menu Bar Commands

| Command | Shortcut | Description |
|---------|----------|-------------|
| Preferences | `,` | Open the preferences window |
| Send Test Bell | `t` | Send a test notification immediately |
| Open Config | `o` | Open config.json in your default editor |
| Reload Config | `r` | Reload config from disk |
| Quit | `q` | Quit Clocktower |

## Notes

- Focus mode exceptions are controlled in **System Settings > Focus** for Clocktower

## License

MIT
