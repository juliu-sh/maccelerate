# Maccelerate 1.1.19 — Free release (build 30)

A free, MIT-licensed macOS menu bar app based on InstantSpaceSwitcher by jurplel.

## Changed

- Remove local build paths and debug/object-file records from the distributed executables.
- Space switching and permission handling match version 1.1.18.

## Included

- Fast Space switching, configurable shortcuts, and Fast/Faster/Instant presets.
- Trackpad override, experimental Mission Control/App Exposé acceleration, and optional Cmd-Tab transition acceleration.
- Native settings for switching and shortcuts; no account or activation required.
- Universal app for Apple Silicon and Intel; deployment target macOS 13.
- Sparkle update controls; automatic checks off by default.
- Included ISSCli, MIT notices and complete Sparkle third-party licenses inside the app.
- Clean drag-and-drop installer with just Maccelerate and the Applications shortcut.

## Compatibility status

macOS 27 switching uses asynchronous phases and confirmation polling. macOS 26 and earlier retain the legacy event path. Some features use undocumented macOS behavior; compatibility can vary between system versions.

## Install

Open the official DMG, drag Maccelerate to Applications, and grant Accessibility and, if requested, Input Monitoring permission. Website, GitHub Releases and the Homebrew Cask use the same official DMG.

See [PRIVACY.md](PRIVACY.md), [NOTICE](NOTICE), and [CREDITS.md](CREDITS.md).
