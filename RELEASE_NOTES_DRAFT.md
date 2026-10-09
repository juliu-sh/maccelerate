# Maccelerate 1.3.1, Free release, build 33

Rapid Space switching now coordinates consecutive requests, including quick
direction reversals. New input updates the destination while a switch is in
progress, so obsolete requests do not build up behind the latest choice.

## Fixes

- Confirm the observed Space before reporting a completed switch, updating the Space indicator or counting it in Statistics.
- Keep track of the latest destination during fast shortcut and trackpad sequences on all supported macOS versions.
- Account for ongoing display transitions when macOS exposes their status. Recover from ignored explicit requests with bounded retries.
- Fail conservatively when a transition cannot be confirmed. A failed or superseded request does not leave an unconfirmed Space prediction behind.
- Preserve each macOS version's gesture format and the existing permission-change protections.

Appearance, the optional Space indicator and local aggregate Statistics remain
included in Free. Maccelerate is free and MIT licensed.

## Compatibility

Rapid shortcut and trackpad switching were tested live on macOS 26.6. Automated
tests also cover both gesture formats, delayed and dropped transitions, rapid
reversals, Space boundaries, cancellation and permission changes. Live coverage
across other macOS versions, displays and full-screen Spaces remains limited.

Maccelerate uses undocumented macOS behavior. If display-animation status is
unavailable, switching uses a conservative confirmation path and can time out
rather than report an uncertain result as successful. If input access is
unavailable, check Accessibility access, then quit and reopen Maccelerate.

## Installation

Download the signed and notarized universal DMG for Apple Silicon and Intel,
open it and drag Maccelerate to Applications. Minimum system version is macOS 13.
Existing installations can use **Check for Updates**. Automatic update checks
remain off by default.
