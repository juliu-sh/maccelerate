# Privacy

Maccelerate processes input events and macOS app, window and Space information locally to switch Spaces and handle shortcuts. It checks key codes and modifiers; it does not record typed text or include analytics or crash reporting. It does not maintain a chronological action history.

## Local statistics

Local statistics are enabled by default. They store aggregate counts by action, speed preset, macOS version and Reduce Motion setting, plus the tracking start date. Counts and the estimated time saved stay in `UserDefaults` on this Mac. They contain no typed text, app names, window titles or event timestamps and are not transmitted. In **Statistics**, you can pause recording without losing prior totals or reset all totals and the start date.

Time saved is an estimate based on reference durations from one screen recording, not a measurement of each transition on your Mac. Results vary by hardware, macOS version and settings.

## Settings and permissions

Switching and shortcut preferences are stored in macOS `UserDefaults` on your Mac. If you enable launch at login, macOS stores that registration. Accessibility and Input Monitoring permissions can be revoked in **System Settings → Privacy & Security**. The app has no account or license activation.

## Updates

Official builds use Sparkle. Automatic checks are off by default; manual checks run when you select “Check for Updates…”. Checks contact `https://raw.githubusercontent.com/juliu-sh/maccelerate/main/appcast.xml`; downloads use public GitHub Releases. Those services receive ordinary HTTP information such as your IP address and user agent. Sparkle system profiling is disabled. Keyboard input, app names and window contents are not sent.

Downloads are verified with the project's Ed25519 update key, and official releases are Developer ID signed and notarized. Installation requires confirmation. Self-built source apps do not use the official update feed.

This document describes the source in this repository. Review it when behavior or dependencies change.
