# Releasing Maccelerate

Maccelerate is prepared for an MIT open-source launch with public GitHub Releases, Sparkle updates, and an own Homebrew tap. The Free app and its source are publicly downloadable without payment or activation. Source and releases are not public until the launch is performed.

## One-time setup

1. Configure the actual GitHub destinations:
   ```sh
   python3 dist/release.py configure --repository OWNER/maccelerate --tap OWNER/homebrew-tap
   gh auth login
   ```
   Replace `OWNER` with the chosen account or organization. Create the repositories and connect `origin` only from the exported public Free checkout. The mixed development checkout must never be pushed: its old history contains excluded features and historical binaries. `dist/export-public.py` exports only the explicit file inventory and optionally initializes a new, unrelated Git history. Run `python3 dist/public_boundary.py --history` there before any push. Do not add the old development checkout as a remote or merge its history.
2. The configured signing identity is `Developer ID Application: Julius Hagen (DK9USXMYX5)`. The notarization credentials are in Keychain profile `Maccelerate-notary`. No credentials are stored in `dist/release-config.json`.
3. Sparkle 2.10.0 is pinned in `Package.swift` and `Package.resolved`. The private Ed25519 key uses Keychain account `maccelerate`. The public key is in `Info.plist`. Back up the private key in encrypted form outside the repository using `dist/backup-update-key.command /absolute/path/to/backup.enc`; enter the encryption password at the local prompt and keep it in your password manager. Never regenerate the key when preparing an update.
4. Serve the generated `appcast.xml` through the public repository at `https://raw.githubusercontent.com/juliu-sh/maccelerate/main/appcast.xml`. Publish the versioned DMG first, then commit the matching feed. The app reads this URL; `maccelerate.app` remains the website domain.
5. Review `PRIVACY.md`, `LICENSE`, `LICENSES/`, `NOTICE`, and assets before launch.

## Prepare a candidate

Increase the patch version and build number for every app change. The current candidate is **1.1.16, build 26**. Keep the bundle identifier stable for updates; it is currently `com.interversehq.Maccelerate`. Any initial move to a Jukes Studio ID must happen before the first public build, with a plan for existing preferences and permissions.

Finish the intended changes, run `bash diagnostics/test-swift.sh`, and commit the reviewed source. Then, from the public Free checkout:

```sh
python3 dist/public_boundary.py --history
./dist/prepare-release.sh
```

The script requires the public Free checkout, builds both architectures, embeds Sparkle, signs nested helpers before their containing framework and app, submits the app to Apple, staples it, creates and signs the DMG, submits and staples the DMG, and verifies Apple's accepted status. It signs the final DMG with Sparkle and creates:

```text
build/release/<version>/
  Maccelerate-<version>.dmg
  Maccelerate-<version>.dmg.sha256
  Maccelerate-<version>-source.zip
  appcast.xml
  release-notes.md
  manifest.json
  Casks/maccelerate.rb
```

`--allow-dirty` is available for a local trial; such a candidate cannot be published by the release tool and does not receive a source ZIP. This does not commit or publish anything. Existing local candidate metadata is not overwritten. Build numbers must exceed all entries in the committed `appcast.xml`.

## Review and draft

Install the DMG on a second Mac. Check Gatekeeper, Accessibility/Input Monitoring permissions, switching, shortcuts, login startup, and quitting. Check the supported macOS versions and Apple Silicon/Intel claims. Test a complete Sparkle update from an older signed and notarized test build using a separate test feed; both builds need the same bundle ID and update public key. Do not publish a fake higher build to the customer feed.

Push the reviewed source commit to the configured GitHub repository, then create a draft:

```sh
python3 dist/release.py draft 1.1.16
```

The tool refuses dirty candidates, changed DMGs, or a source commit that no longer matches. The draft contains the exact DMG, checksum, source ZIP and appcast. Review release notes and the downloaded asset before launch.

## Publish in order

After the candidate and customer flow have been tested:

```sh
python3 dist/release.py publish 1.1.16
```

This checks the draft DMG checksum and makes the GitHub Release public. It does not deploy a website or push a Homebrew tap automatically.

1. Verify the public versioned DMG URL works without authentication.
2. Deploy `build/release/<version>/appcast.xml` to the configured feed. If using the GitHub latest-release redirect, publishing the release already makes its appcast available. Test the final URL and download signature.
3. Copy the generated `Casks/maccelerate.rb` into the separate `homebrew-tap` repository. Run `brew style` and `brew audit --cask --online` against the cask, then commit and push it. Install with `brew install --cask OWNER/tap/maccelerate`. `auto_updates true` declares Sparkle support; explicit Homebrew upgrades can use `brew upgrade --cask --greedy maccelerate`.
4. Copy the published appcast back to this repository and commit it, preserving older entries for future releases.
5. Update the website links and announcement. The website must describe the free download and included features accurately.

Never replace assets for a published version. Prepare a new version and build for corrections. Apple and Sparkle private signing keys stay on the development Mac; this workflow does not upload them to GitHub Actions.

## Licenses and source

The app and DMG include MIT, the original InstantSpaceSwitcher MIT notice, Sparkle's complete third-party licenses, and attribution. The source ZIP uses the exact `dist/public-files.json` inventory; its contents and the complete Git history are checked by `dist/public_boundary.py`. Publish only from the newly exported public checkout. Premium code, local launch notes, website drafts, binaries and the mixed development history are excluded. Unknown files fail the publication gate until intentionally added to the inventory. MIT permits redistribution of both source and binaries with the required notices.

The app relies on undocumented macOS behavior and a private framework. This workflow targets direct distribution, not the Mac App Store.
