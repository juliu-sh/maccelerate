# Maccelerate 1.1.18 — Free release candidate (build 29)

A free, MIT-licensed macOS menu bar app based on InstantSpaceSwitcher by jurplel.

## Status

Pre-release candidate for a blocking permission-lifecycle defect. The prior 1.1.17 must not be published. Live verification of permission withdrawal and macOS 27 acceleration is required before release.

## Changed

- Start input processing and global shortcuts only after Accessibility and event-posting access are available.
- Stop processing after a system/user tap disable instead of re-enabling it.
- Cancel pending asynchronous gestures on permission loss and limit repeated timeout recovery.
- Show the actual input connection status and require an app restart after input has been suspended.

## Included

- Fast Space switching, configurable shortcuts, and Fast/Faster/Instant presets.
- Trackpad override, experimental Mission Control/App Exposé acceleration, and optional Cmd-Tab transition acceleration.
- Native settings for switching and shortcuts; no account or activation required.
- Universal app for Apple Silicon and Intel; deployment target macOS 13.
- Sparkle update controls; automatic checks off by default.
- Included ISSCli, MIT notices and complete Sparkle third-party licenses inside the app.
- Clean drag-and-drop installer with just Maccelerate and the Applications shortcut.

## Compatibility status

macOS 27 switching uses asynchronous phases and confirmation polling. macOS 26 and earlier retain the legacy event path. Live acceptance on the supported systems and a complete Sparkle update test remain release checks. Do not describe this candidate as publicly released until notarization and installation checks are complete.

## Install

Open the official DMG, drag Maccelerate to Applications, and grant Accessibility and, if requested, Input Monitoring permission. Website, GitHub Releases and the Homebrew Cask use the same official DMG.

See [PRIVACY.md](PRIVACY.md), [NOTICE](NOTICE), and [CREDITS.md](CREDITS.md).
