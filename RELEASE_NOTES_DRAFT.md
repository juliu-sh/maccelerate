# Maccelerate 1.1.20 — Free release (build 31)

Maccelerate is a free, MIT-licensed macOS menu bar app based on InstantSpaceSwitcher by jurplel.

## Changes

- Restore distinct Fast, Faster and Instant Space-switching presets on macOS 27.0 build 26A428.
- Add neutral trackpad gesture completion and recovery after one second of missing gesture activity on that build.
- Handle rejected and interrupted trackpad switch requests without repeatedly submitting the same swipe.
- Make missing or stopped Accessibility access easier to see in the settings window, including when the window is inactive.
- Remove local build paths and debug/object-file records from distributed executables.

## Compatibility

The updated speed and trackpad recovery behavior is currently limited to macOS 27.0 build 26A428. Other macOS 27 builds retain their existing behavior. macOS 26 and earlier retain the existing switching path.

Automated checks cover gesture completion, interrupted requests, recovery timing, malformed payloads and the macOS 26 reference event sequence. Full live validation across multiple displays, full-screen Spaces and rapid gesture sequences remains incomplete. These changes do not establish that every intermittent trackpad failure is resolved.

The app uses some undocumented macOS behavior, so compatibility can vary between system builds. If the settings window reports that input has stopped or access is unavailable, check Accessibility access, then quit and reopen Maccelerate.

## Installation

Download the signed and notarized universal DMG for Apple Silicon and Intel, open it and drag Maccelerate to Applications. Minimum system version: macOS 13. Grant Accessibility and, if requested, Input Monitoring access.

Existing installations can use **Check for Updates**. Automatic update checks remain off by default. The app includes ISSCli and the Maccelerate, InstantSpaceSwitcher and Sparkle license notices.
