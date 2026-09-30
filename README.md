# Maccelerate

A free, MIT-licensed macOS menu bar app that accelerates switching between Spaces. Based on [InstantSpaceSwitcher](https://github.com/jurplel/InstantSpaceSwitcher) by jurplel; the original MIT notice is retained in [LICENSES/InstantSpaceSwitcher-MIT.txt](LICENSES/InstantSpaceSwitcher-MIT.txt).

## Features

- Fast native Space switching, without disabling System Integrity Protection.
- Configurable shortcuts and three speed presets: Fast, Faster, and Instant.
- Optional trackpad gesture override and Mission Control/App Exposé acceleration.
- Optional acceleration of Cmd-Tab transitions when the destination is unambiguous.
- Menu bar controls, launch at login, and settings for switching and shortcuts.
- Sparkle updates in official builds, with automatic checks off by default.
- Included command-line tool: `Maccelerate.app/Contents/MacOS/ISSCli --help`.

## Requirements and permissions

Targets macOS 13 or later. Official packaging builds both Apple Silicon and Intel. Some switching behavior uses undocumented macOS APIs; a future system update can affect compatibility. Automated tests do not replace live tests on supported systems.

Grant Accessibility and, if requested, Input Monitoring in **System Settings → Privacy & Security**. Input and app/window information are processed locally; there is no telemetry. See [PRIVACY.md](PRIVACY.md).

## Build from source

Install a matching full Xcode toolchain, then run:

```sh
bash diagnostics/test-swift.sh
python3 diagnostics/test-public-boundary.py
python3 diagnostics/test-release.py
./dist/build.sh
./dist/deploy-to-dmg.sh
```

The app is in `build/Maccelerate.app`; the DMG is in `build/Maccelerate-<version>.dmg`. Sparkle is pinned in `Package.resolved`, and licenses are bundled inside the app. The DMG shows only Maccelerate and the Applications shortcut.

Own builds use the separate bundle ID `com.interversehq.Maccelerate.source`, a local/ad hoc signature, and no official update feed. They may require manual approval on another Mac. Quit the official app before running your own build so two event taps do not process input at once. Rebranding or redistributing a fork requires your own signing and update configuration.

## Official releases

Official builds use Developer ID signing, notarization, GitHub Releases and an optional Homebrew tap. The app is free; no account, purchase, or license activation is required. Only official builds use the configured HTTPS update feed. See [RELEASING.md](RELEASING.md) for the release process. Download [Free 1.1.18](https://github.com/juliu-sh/maccelerate/releases/tag/v1.1.18), or install via `brew install --cask juliu-sh/tap/maccelerate`. If input processing stops after permission changes, check access, then quit and reopen Maccelerate.

## License and credits

Maccelerate source in this repository is [MIT licensed](LICENSE). InstantSpaceSwitcher-derived code retains its original MIT notice, including combined source files. Sparkle notices are in [LICENSES/Sparkle.txt](LICENSES/Sparkle.txt). See [NOTICE](NOTICE) and [CREDITS.md](CREDITS.md). Previously distributed copies retain the permissions granted with those copies.
