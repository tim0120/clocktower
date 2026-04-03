# Clocktower

A small native macOS menu bar app that sends timed reminders at regular intervals.

## Features

- Lives in the menu bar — no dock icon, no windows in the way
- Sends local notifications with configurable title, body, sound, and interval
- Global on/off control from the menu bar and preferences
- Quiet hours support so reminders stay off during a daily time range
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

After install:

1. Open Clocktower from your menu bar.
2. Open **Preferences** and set your interval, sound, and optional quiet hours.
3. Use **Send Test Bell** to confirm notifications look right.

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

Clocktower stores only local app state:

- `config.json` for settings
- `clocktower.log` for runtime logs
- `install.log` for installer runs
- `clocktower.lock` for single-instance protection

Default config:

```json
{
  "bodyTemplate": "It's {{time}}.",
  "isEnabled": true,
  "intervalMinutes": 30,
  "quietHoursEnabled": false,
  "quietHoursEndMinutes": 540,
  "quietHoursStartMinutes": 1080,
  "soundName": "Tink",
  "suppressWhenPresenting": false,
  "title": "Clocktower"
}
```

| Field | Description |
|-------|-------------|
| `isEnabled` | Master switch for all reminders |
| `intervalMinutes` | Minutes between reminders (minimum 1) |
| `title` | Notification title |
| `bodyTemplate` | Notification body. `{{time}}` is replaced with the current time |
| `soundName` | macOS system sound name, or `null` for default |
| `suppressWhenPresenting` | Skip notifications when a presentation app is the frontmost window |
| `quietHoursEnabled` | Turns the quiet-hours schedule on or off |
| `quietHoursStartMinutes` | Minutes after midnight when Clocktower should turn off |
| `quietHoursEndMinutes` | Minutes after midnight when Clocktower should turn back on |

## Menu Bar Commands

| Command | Shortcut | Description |
|---------|----------|-------------|
| Enable/Disable Clocktower | - | Turn reminders on or off immediately |
| Preferences | `,` | Open the preferences window |
| Send Test Bell | `t` | Send a test notification immediately |
| Open Config | `o` | Open config.json in your default editor |
| Open Logs | `l` | Open the Clocktower runtime log |
| Reload Config | `r` | Reload config from disk |
| Quit | `q` | Quit Clocktower |

## Notes

- Focus mode exceptions are controlled in **System Settings > Focus** for Clocktower
- New builds now use a shared lock file in `~/Library/Application Support/Clocktower/clocktower.lock` so only one Clocktower process can run even if multiple app variants exist
- Runtime logs are written to `~/Library/Application Support/Clocktower/clocktower.log`
- Installer logs are appended to `~/Library/Application Support/Clocktower/install.log`

## Troubleshooting

- If reminders stop entirely, check that Clocktower is enabled in the menu bar and that your current time is outside quiet hours.
- If notifications do not appear, confirm Clocktower is allowed in **System Settings > Notifications**.
- If behavior looks wrong after reinstalling, open **Open Logs** from the menu bar and inspect `clocktower.log`.

## License

MIT
