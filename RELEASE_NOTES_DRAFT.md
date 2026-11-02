# Maccelerate 1.4.0, Free release, build 34

Maccelerate now accelerates the keyboard shortcuts you already use in macOS
and adds optional Stage Manager settings.

## New

- **macOS shortcuts:** Move left/right a space, Switch to Desktop 1–10, Mission Control and Application windows use Maccelerate's switching speed when they are enabled in System Settings. Maccelerate reads these settings and does not change them. Shortcuts that are turned off in macOS are left alone. You can turn this off in **Shortcuts**.
- **Additional shortcuts:** Your own key combinations are now a separate, optional list with a single switch. New default combinations for Mission Control and App Exposé are Control-Option-Command-Up/Down Arrow, so they no longer overlap macOS's own shortcuts. Shortcuts you already set are kept.
- **Stage Manager animation speed:** Choose Fast, Faster or Instant, or keep the System setting. The change applies immediately.
- **Show recent apps instantly:** Removes the wait at the screen edge before Stage Manager's recent apps appear. Stage Manager applies this after a restart, which Maccelerate can do for you; your windows stay open.
- **Shift-click in the Dock adds to stage (experimental, off by default):** Adds an open app to the current stage instead of switching to its own stage. This works for apps shown in Stage Manager's recent apps; other clicks behave as usual.

The Stage Manager options use hidden macOS settings. They stay in macOS after
Maccelerate quits until you choose System or turn the option off.

## Compatibility

The new shortcut handling and the Stage Manager options were tested live on
macOS 26.6. Automated tests cover the shortcut reading and translation. Live
coverage across other macOS versions, keyboard layouts and display arrangements
remains limited. Stage Manager options rely on undocumented behavior that a
macOS update can change or ignore.

## Installation

Download the signed and notarized universal DMG for Apple Silicon and Intel,
open it and drag Maccelerate to Applications. Minimum system version is macOS 13.
Existing installations can use **Check for Updates**. Automatic update checks
remain off by default.
