# Contributing to fan

The most valuable contributions improve hardware compatibility, safety, reliability, accessibility, and documentation.

## Before opening a pull request

1. Open an issue for changes that affect SMC writes, privilege handling, or thermal policy.
2. Keep fan-control changes small and explain their safety properties.
3. Do not add analytics, account requirements, advertising, or unrelated network access.
4. Test the system-control restoration path before requesting review.

## Local checks

```bash
swift test
xcodebuild \
  -project fan.xcodeproj \
  -scheme fan \
  -configuration Debug \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

You can also run the project workflow:

```bash
./script/build_and_run.sh --verify
```

## Compatibility reports

Please include:

- Mac model and year
- Chip family
- macOS version
- Number of detected fans
- Which temperatures and RPM values appear
- A diagnostics export with any private information reviewed first

## Style

- Follow Swift API Design Guidelines.
- Keep SwiftUI views focused and state ownership explicit.
- Prefer deterministic policy functions that can be tested without SMC hardware.
- Preserve keyboard access, focus visibility, reduced motion, and system colour adaptation.

