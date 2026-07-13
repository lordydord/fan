# Changelog

This repository begins a new public release line for `fan`.

## 1.1.2 - 2026-07-12

### Power monitoring

- Fixed power usage remaining at 0.0 W when a fully charged Mac is connected to AC power.
- Switched the primary reading to macOS live system-load telemetry.
- Kept voltage and battery-current calculation as a fallback for Macs without system-load telemetry.
- Added regression coverage for AC-powered and battery-powered readings.

## 1.1 - 2026-07-12

### Interface

- Renamed the visible product branding to Fan App.
- Moved settings into the menu bar popover instead of opening a separate window.
- Redesigned settings to match the dashboard's amber, material-based visual system.
- Replaced the directional settings transition with a smooth crossfade.
- Applied reduced-motion preferences to page, meter, and button animations.

### Cooling control

- Fixed Max so it commands every detected fan to the configured 6,500 RPM ceiling.
- Added an explicit Custom profile state for manually adjusted controls.
- Persisted the selected profile across clean app restarts.

### Reliability and release

- Added regression coverage for one-fan, two-fan, and zero-fan maximum targets.
- Made release builds, downloads, and GitHub publishing version-driven.
- Refreshed the installed app and release packaging for the Fan App 1.1 line.

## 1.0.0 - 2026-07-12

### Interface

- Introduced a new thermal cockpit for the menu bar popover.
- Added live temperature, RPM, power, and fan-count telemetry.
- Added System, Quiet, Balanced, Performance, and Max profiles.
- Added responsive native popover sizing across every profile and state.
- Rebuilt setup, loading, access, and error states.
- Refined settings into a dedicated macOS window.

### Cooling control

- Added Smart control with adjustable threshold and response.
- Added precise manual RPM control.
- Added a timed 10 minute maximum-cooling boost.
- Added per-fan control and hardware-bound speed clamping.
- Added configurable emergency maximum-speed protection.

### Reliability

- Added adaptive monitoring intervals to reduce unnecessary polling.
- Added serialized SMC access and guarded concurrent reads.
- Added a watchdog that restores macOS fan control after abnormal exit.
- Added sleep, wake, lock, and unlock restoration handling.
- Fixed the popover lifecycle race that could require repeated clicks.

### Diagnostics and documentation

- Added diagnostics export.
- Added Swift Package Manager tests for the thermal control policy.
- Added a one-command local build, run, and verification workflow.
- Added a complete product site, security notes, and release documentation.
