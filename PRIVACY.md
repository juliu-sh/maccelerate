# Privacy

Maccelerate processes input events and macOS app, window and Space information locally to switch Spaces and handle shortcuts. It checks key codes and modifiers; it does not record typed text or include analytics or crash reporting. This Free edition does not collect usage counts or maintain an action history.

## Settings and permissions

Switching and shortcut preferences are stored in macOS `UserDefaults` on your Mac. If you enable launch at login, macOS stores that registration. Accessibility and Input Monitoring permissions can be revoked in **System Settings → Privacy & Security**. The app has no account or license activation.

## Updates

Official builds use Sparkle. Automatic checks are off by default; manual checks run when you select “Check for Updates…”. Checks contact `https://raw.githubusercontent.com/juliu-sh/maccelerate/main/appcast.xml`; downloads use public GitHub Releases. Those services receive ordinary HTTP information such as your IP address and user agent. Sparkle system profiling is disabled. Keyboard input, app names and window contents are not sent.

Downloads are verified with the project's Ed25519 update key, and official releases are Developer ID signed and notarized. Installation requires confirmation. Self-built source apps do not use the official update feed.

This document describes the source in this repository. Review it when behavior or dependencies change.
