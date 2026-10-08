# Releasing Maccelerate

Official Free releases are MIT licensed and distributed through GitHub Releases,
Sparkle and the [Homebrew tap](https://github.com/juliu-sh/homebrew-tap).
For a local source build, follow [README.md](README.md); Apple signing credentials
are only needed for distribution.

## Repository and channel responsibilities

This repository is the only app source and production build repository. The
Homebrew tap is a separate repository containing the generated cask; the
website is deployed separately. Never merge historical mixed/private history,
app backups, website data or local release notes into this repository.
There is one shipped app, Maccelerate Free, including Appearance/HUD and local
Statistics. Source builds are development tools, not another product/channel.

Publish in this order: verified GitHub assets, matching Sparkle feed, matching
Homebrew cask, then the website download URL. All channels must refer to the
same immutable DMG and checksum. Preparing documentation or a candidate does
not publish anything; public changes require a release request.

## Publication checks

After cloning, run `./dist/install-publication-guard.sh` to enable this checkout's
pre-push check. CI and release tools also check the complete public inventory,
Git history, source archives and release notes for private credentials, local
machine paths and internal publication metadata. Release binaries have debug path
records removed before signing and are checked before packaging.

Older nonsecret metadata is accepted only in the already-published ancestors of
the initial documentation cleanup. New commits and all new archives are strict;
`python3 dist/public_boundary.py --strict-history` also reports historical metadata.
The guard is a check, not a guarantee against every kind of sensitive content.
Review the exact files and release notes before uploading.

## Distribution setup

Use a Developer ID Application certificate and a validated `notarytool` Keychain
profile. Keep certificates, passwords and private update keys outside the repository.

Public destinations are in `dist/release-config.json`. Local signing settings go in
**`dist/release-config.local.json`**, which is ignored by Git:

```json
{
  "signing_identity": "Developer ID Application: YOUR NAME (YOUR TEAM ID)",
  "notary_profile": "YOUR KEYCHAIN PROFILE",
  "sparkle_account": "YOUR SPARKLE KEYCHAIN ACCOUNT"
}
```

These values identify existing Keychain entries; do not put passwords or keys in
this file. The local file only accepts these three fields. Signing and notarization
can also use `MACCELERATE_CODESIGN_IDENTITY` and `MACCELERATE_NOTARY_PROFILE`.

Forks need their own bundle ID, GitHub destinations, HTTPS feed and Sparkle key.
Configure destinations with `python3 dist/release.py configure --repository
OWNER/APP --tap OWNER/homebrew-tap`, and update `SUFeedURL` in `Info.plist` to match.
For an existing update channel, preserve its bundle ID and signing key. Back up
update keys encrypted outside the repository with `dist/backup-update-key.command`.

## Local builds and backups

Source builds use `Maccelerate Source.app` and a separate bundle ID. Keep them
separate from `/Applications/Maccelerate.app`. An official update must preserve
the production bundle ID and Developer ID signing requirement. Before diagnosing
permission loss, check the running app's path, bundle ID and signing requirement.
Quit the app before removing or resetting its permission entries.

Save app backups as ZIP archives, not loose `.app` copies or versioned app bundles.
Use `python3 dist/archive-app.py APP BACKUP.zip` to create a backup and verify
its restored contents and existing signature without registering another app. Extract into a temporary directory and
verify the signature and file contents before retiring the original. Do not keep
extracted verification bundles. Keep local backups outside the public inventory.
`dist/build.sh --clean` archives the previous build in ignored `build-backups/`
and verifies the ZIP before cleaning, preserving earlier local candidates.
Changing build channels also archives and retires the other channel's app.
Quit any app running from the checkout's build directory before rebuilding it.

## Prepare and test

1. Increase the app version and build number in `Info.plist`. Builds must exceed
   every entry in `appcast.xml`; published versions must not be reused.
2. Update product-facing `RELEASE_NOTES_DRAFT.md`, then run:

   ```sh
   bash diagnostics/test-swift.sh
   python3 diagnostics/test-build-workflow.py
   python3 diagnostics/test-public-boundary.py
   python3 diagnostics/test-release.py
   ```

   Commit only the reviewed public source files. Keep local release configuration
   ignored and leave the working tree clean.
3. From this public checkout, run:

   ```sh
   python3 dist/public_boundary.py --history
   ./dist/prepare-release.sh
   ```

The script builds both architectures, signs and notarizes the app and DMG, then
creates checksums, a source ZIP, signed appcast, release notes, a manifest and a
Homebrew cask in `build/release/<version>/`. Nothing is published by this step.
`--allow-dirty` is for local trials only; those candidates cannot be published.

Test the exact DMG on another Mac: installation, permissions, switching,
shortcuts, login startup and quitting. Verify a full Sparkle update using a
separate test feed. Keep untested builds off the official feed.

## Publish

Push the reviewed source, then create and review the draft:

```sh
python3 dist/release.py draft VERSION
python3 dist/release.py publish VERSION
```

The release tool verifies the source commit and candidate checksums. Publish the
DMG first, verify its public download, then commit the matching appcast and update
the separate Homebrew tap from the generated cask. Check the cask with Homebrew's
style and online audit tools. Update the website download URL only after the
public DMG, feed and cask agree. Deploy only the reviewed website inventory,
excluding environment files, internal notes, signup records, Git history and
app binaries. Preserve hosting variables, tracking and persistent signup data;
verify the normal main/www pages and download target after deployment.

Record the built source tag, feed/tap commits, DMG hash and validation locally.
Feed documentation commits do not replace the immutable built source tag.

Keep published app assets immutable; corrections need a new version and build.
The source ZIP uses the exact `dist/public-files.json` inventory. The publication
gate checks sources, complete Git history and archives; check the app with
`python3 dist/public_boundary.py --app build/Maccelerate.app`.

## Licenses

Preserve Maccelerate's MIT license, the original InstantSpaceSwitcher MIT notice,
attribution and Sparkle's complete third-party licenses. Notices are bundled
inside the app; the DMG contains the app and Applications shortcut.

The app uses undocumented macOS APIs and targets direct distribution.
