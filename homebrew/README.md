# Maccelerate Homebrew tap

The cask is generated from the final signed and notarized DMG by `python3 dist/release.py assets`. Its version, SHA-256 checksum and download URL match the Sparkle release.

Configure an own repository named `homebrew-tap` in `dist/release-config.json`. Copy `build/release/<version>/Casks/maccelerate.rb` into that repository's `Casks/` folder, validate it, and publish it only after the referenced GitHub Release is available. No placeholder or old development DMG should be used.

Users can install with `brew install --cask OWNER/tap/maccelerate` after replacing `OWNER` with the actual GitHub account. The cask declares `auto_updates true`; Sparkle can update the installed app normally. An explicit Homebrew upgrade can use `brew upgrade --cask --greedy maccelerate`.

An own tap does not require acceptance into the central `homebrew/cask` repository. The generated cask intentionally has no `zap` rule that removes user preferences.
