# Changelog

This repository begins a new public release line for `fan`.

## 1.2.1 - 2026-10-29

### Fixes

- Fixed the app quitting itself when the lid was closed. Sleep and display sleep arrive together; the second notification re-entered the fan hand-back while the first was still waiting on the helper, and macOS stopped the app (crash reports since 23 Oct, all in `FanController.restoreSystemControl`). Sleep is now handled once, and helper commands wait without spinning the run loop.
- Installed on the MacBook on 29 Oct 2026; the previous 1.2.0 app is kept at `releases/installed-backup-1.2.0/fan.app`.

## 1.2.0 - 2026-10-01

### Settings that stay put

- Moved every choice into one settings store that saves the moment it changes; nothing else writes those values.
- Boost, Max, emergency cooling and "switch to Smart when hot" are now temporary states held in memory, so they can no longer overwrite your saved manual speed, profile or mode.
- Sleep, display sleep, lock and shutdown hand the fans to macOS without touching your settings; on wake the app re-applies exactly what you chose, once, after a short settle.
- Open at login re-registers itself on launch if macOS has dropped the login item after an app update.
- One-time migration from 1.1.x: the old System and Max profiles become modes, and a manual speed left at 6,500 RPM by Max or Boost resets to 3,000 RPM.

### Performance

- Sensor keys are found once and remembered; keys a Mac does not have are never queried again (previously up to nine failed SMC calls on every reading on Apple silicon).
- Fan minimum and maximum speeds are read once at start-up instead of on every reading.
- Fan-speed commands run on a background queue, so the menu and popover never wait on the helper.
- The menu bar only redraws when its reading changes, and the sensor timer allows macOS to batch wake-ups.
- Removed unused SMC write, powermetrics and demo-mode code.

### Interface

- Redesigned the popover and settings to match Claude Usage: Liquid Glass cards, twin gradient rings for temperature and fan speed, a temperature trend line, a single Cooling card and a teal Boost card.
- Cooling is now four clear modes (macOS, Smart, Manual, Max), with Quiet, Balanced, Performance and Custom profiles inside Smart, plus a top-speed slider.
- Boost shows a live countdown and the mode it returns to.
- Right-click menu shows a tick next to the current mode and adds Quit.
- Narrower 320 pt popover, lighter menu bar reading.

## 1.1.4 - 2026-07-21

### Interface

- Rebuilt the dashboard and settings surfaces with native macOS Liquid Glass.
- Added restrained amber and temperature-aware glass tinting while keeping the interface clear and readable.
- Refined popover buttons, profile controls, metric chips, and settings sections with consistent translucent materials and borders.
- Preserved the existing in-popover Settings and Back navigation flow.

## 1.1.3 - 2026-07-13

### Smart cooling

- Fixed Maximum response incorrectly holding fans at maximum RPM below the target temperature.
- Made every response level return toward minimum fan speed at or below the selected target.
- Changed stronger responses to ramp earlier and harder only after the temperature exceeds the target.
- Preserved the separate Max profile and emergency-temperature override as true full-speed controls.
- Added regression coverage for below-target ramp-down and relative response strength above target.

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
