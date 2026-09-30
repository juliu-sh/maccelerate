# Releasing Maccelerate

Official Free releases are MIT licensed and distributed through GitHub Releases,
Sparkle and the [Homebrew tap](https://github.com/juliu-sh/homebrew-tap).
For a local source build, follow [README.md](README.md); Apple signing credentials
are only needed for distribution.

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

## Prepare and test

1. Increase the app version and build number in `Info.plist`. Builds must exceed
   every entry in `appcast.xml`; published versions must not be reused.
2. Update `RELEASE_NOTES_DRAFT.md`, run `bash diagnostics/test-swift.sh` and commit
   the reviewed changes.
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
style and online audit tools. Update website links after downloads are available.

Keep published app assets immutable; corrections need a new version and build.
The source ZIP uses the exact `dist/public-files.json` inventory. The publication
gate checks sources, complete Git history and archives; check the app with
`python3 dist/public_boundary.py --app build/Maccelerate.app`.

## Licenses

Preserve Maccelerate's MIT license, the original InstantSpaceSwitcher MIT notice,
attribution and Sparkle's complete third-party licenses. Notices are bundled
inside the app; the DMG contains the app and Applications shortcut.

The app uses undocumented macOS APIs and targets direct distribution.
