# Maccelerate 1.3.0, Free release, build 32

Appearance settings and Statistics are now included in Free. Maccelerate remains
free and MIT licensed, with no account, purchase or license activation required.

## New in Free

- Appearance settings with an optional Space indicator, configurable display duration and a preview.
- A Statistics tab with local counts by action and speed, estimated time saved, and pause and reset controls.

Statistics are enabled by default and stay on your Mac. They store aggregate
counts, not typed text, app names, window contents or an event timeline. The time
saved figure is an estimate based on reference animation durations. You can pause
recording or reset the stored counts in Settings. See [PRIVACY.md](https://github.com/juliu-sh/maccelerate/blob/v1.3.0/PRIVACY.md).

## Fixes

- Apply the macOS-27 Space-switching speed and trackpad recovery fixes on macOS 27 and later. Minor versions such as 27.0.1 and Apple build numbers no longer disable them.
- Suppress accidental software-generated middle clicks during accelerated vertical swipes into Mission Control and App Exposé, including three-finger taps interpreted by Supercharge. Keep suppressed press and release events paired by their source.
- Preserve hardware middle clicks and deliberate taps outside the guarded gesture. Clear the guard when input processing stops or access changes.

macOS 26 and earlier retain the existing Space-switching path. The vertical
middle-click correction applies on all supported macOS versions.

## Compatibility

Maccelerate uses some undocumented macOS behavior. Automated tests cover version
routing, gesture completion and recovery, malformed payloads, permission changes,
and accidental middle-click pairing. Live coverage across macOS-27 builds,
multiple displays, full-screen Spaces and rapid gesture sequences remains
limited. This release does not establish that every intermittent trackpad failure
is resolved.

If Settings reports that input has stopped or access is unavailable, check
Accessibility access, then quit and reopen Maccelerate.

## Installation

Download the signed and notarized universal DMG for Apple Silicon and Intel,
open it and drag Maccelerate to Applications. Minimum system version is macOS 13.
Grant Accessibility and, if requested, Input Monitoring access.

Existing installations can use **Check for Updates**. Automatic update checks
remain off by default. The app includes ISSCli and the Maccelerate,
InstantSpaceSwitcher and Sparkle license notices.
