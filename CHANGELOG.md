# Changelog

This repository begins a new public release line for `fan`.

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
