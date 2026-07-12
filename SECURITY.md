# Security

fan reads and writes System Management Controller values. Fan-speed writes require elevated privileges on macOS, so the privilege boundary is intentionally narrow.

## Privileged helper

- Installed path: `/usr/local/bin/smc-helper`
- Owner: `root:wheel`
- Mode: `4755`
- Accepted operations: restore automatic mode and set validated fan targets
- Main application privilege: standard user

The helper source is available in [`tools/smc-helper`](tools/smc-helper). Review it before installation if you maintain a high-security Mac.

## Safety controls

- RPM values are clamped to configured and detected limits.
- Emergency protection can force maximum cooling at a chosen temperature.
- A watchdog restores macOS control if fan exits unexpectedly.
- Sleep, lock, and normal application exit restore automatic control.
- The app does not lower the detected hardware minimum through the public controls.

## Data handling

fan does not require an account and does not upload thermal readings, diagnostics, hardware identifiers, or usage analytics. Exported diagnostics stay on the Mac until the user chooses to share them.

## Reporting a vulnerability

Do not open a public issue for an exploitable privilege-boundary problem. Use GitHub's private vulnerability reporting feature on this repository. Include the affected version, Mac model, macOS version, reproduction steps, and expected impact.

## Removing the helper

```bash
sudo rm /usr/local/bin/smc-helper
```

After removal, fan can continue displaying supported readings but cannot write fan targets.

