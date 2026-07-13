# fan documentation

fan is a native macOS menu bar utility for thermal monitoring and fan control.

## Getting started

1. Download the DMG from [GitHub Releases](https://github.com/lordydord/fan/releases/latest).
2. Drag `fan.app` into Applications.
3. Right-click the app and choose Open on first launch.
4. Open fan from the menu bar.
5. Select Install helper and approve the administrator prompt once.

The v1.1.3 binary requires macOS 26.1 or later and targets Apple Silicon.

## Dashboard

The dashboard shows:

- CPU temperature
- current fan RPM
- detected fan count
- battery power draw when available
- active profile
- current control mode

### Profiles

| Profile | Behaviour |
| --- | --- |
| System | Immediately restores macOS automatic fan control. |
| Quiet | Uses a later threshold and gentler response. |
| Balanced | Uses an everyday temperature and response profile. |
| Performance | Starts stronger cooling earlier. |
| Max | Runs each detected fan at its reported hardware maximum. |

### Smart control

Smart control calculates a target speed from the hottest available CPU or GPU reading. The cooling threshold controls when the response begins. Response controls how quickly fan speed approaches the selected maximum.

### Manual control

Manual control holds the selected target RPM. Values are clamped to supported limits before reaching the helper.

### 10 minute boost

Boost temporarily applies maximum cooling. At the end of the timer, fan restores the previous mode, target, and profile.

## Menu bar

Settings can show one of four menu bar states:

- temperature
- power usage
- fan-speed percentage
- icon only

Right-click the menu bar item for profile shortcuts.

## Settings

Settings includes:

- launch at login
- menu bar display mode
- monitoring interval
- temperature alerts
- automatic high-temperature switching
- emergency cooling threshold
- independent per-fan targets
- diagnostics export
- demo data

## Helper and privileges

macOS restricts SMC writes. fan installs a small helper at `/usr/local/bin/smc-helper`, owned by `root:wheel` with mode `4755`.

The main application runs as the logged-in user. Read the complete [security model](../SECURITY.md) before deploying fan in a managed or sensitive environment.

### Remove the helper

```bash
sudo rm /usr/local/bin/smc-helper
```

## Diagnostics

Choose Export Diagnostics in Settings to save a local text file containing application state and detected readings. Review the file before sharing it publicly.

## Troubleshooting

### No temperatures appear

- Confirm the Mac exposes compatible SMC sensor keys.
- Try Demo Data to verify that the interface is working.
- Export diagnostics and include the Mac model in a compatibility report.

### Fan speed does not change

- Confirm `/usr/local/bin/smc-helper` exists and is executable.
- Reinstall the helper from the app.
- Choose System, then reapply the desired profile.

### The app does not open normally

The v1.1.3 download is ad-hoc signed. Right-click `fan.app`, choose Open, and confirm the standard macOS prompt.

### Restore system control from Terminal

Quit fan first. The watchdog normally restores macOS control automatically. If the helper is installed, you can inspect its supported commands in `tools/smc-helper` before using it directly.

## Development

```bash
swift test
./script/build_and_run.sh --verify
```

The Xcode project is `fan.xcodeproj` and the runnable scheme is `fan`.

## More information

- [Fan App 1.1.3 release notes](release-notes/v1.1.3.md)
- [Fan App 1.1.2 release notes](release-notes/v1.1.2.md)
- [Fan App 1.1 release notes](release-notes/v1.1.md)
- [fan 1.0 release notes](release-notes/v1.0.0.md)
- [Security policy](../SECURITY.md)
- [Contributing](../CONTRIBUTING.md)
- [MIT License](../LICENSE)
