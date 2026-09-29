#!/usr/bin/env python3
"""Exercise release rejection gates without credentials or external writes."""
import importlib.util
import json
import pathlib
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

spec = importlib.util.spec_from_file_location("release", pathlib.Path(__file__).resolve().parents[1] / "dist/release.py")
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        self.config = {"github_repository": "test-owner/maccelerate", "homebrew_repository": "test-owner/homebrew-tap", "feed_url": "https://maccelerate.app/appcast.xml", "sparkle_account": "maccelerate"}
        self.config_path = self.root / "config.json"
        self.config_path.write_text(json.dumps(self.config))
        for name, value in (("ROOT", self.root), ("CONFIG", self.config_path)):
            p = patch.object(release, name, value)
            p.start()
            self.addCleanup(p.stop)
        self.info = {"CFBundleShortVersionString": "1.1.15", "CFBundleVersion": "23", "SUPublicEDKey": "public-key", "SUFeedURL": self.config["feed_url"], "LSMinimumSystemVersion": "13.0", "MaccelerateBuildChannel": "official", "MaccelerateEdition": "free", "GitCommitHash": "test-commit"}
        self.app_info = self.root / "build/Maccelerate.app/Contents/Info.plist"
        self.app_info.parent.mkdir(parents=True)
        self.write_info()
        (self.root / "build/Maccelerate-1.1.15.dmg").write_bytes(b"fixture-dmg")
        (self.root / "appcast.xml").write_text('<rss version="2.0"><channel><title>Maccelerate</title></channel></rss>')
        (self.root / "RELEASE_NOTES_DRAFT.md").write_text("Fixture release notes")
        self.commands = []
        def run(*args):
            self.commands.append(tuple(str(a) for a in args))
            if "generate_keys" in str(args[0]): return "public-key"
            if "sign_update" in str(args[0]): return "signature" if "-p" in args else ""
            if args[:3] == ("git", "status", "--porcelain"): return " M fixture"  # Local trial.
            if args[:3] == ("git", "rev-parse", "HEAD"): return "test-commit"
            if args[:3] == ("git", "rev-parse", "--short"): return "test-commit"
            return ""
        self.mock_run = patch.object(release, "run", side_effect=run).start()
        # The boundary validator has its own real-files/history/archive tests.
        for name in ("audit_history", "audit_app", "audit_archive"):
            patch.object(release.public_boundary, name).start()
        self.addCleanup(patch.stopall)

    def write_info(self):
        self.app_info.write_bytes(plistlib.dumps(self.info))
        (self.root / "Info.plist").write_bytes(plistlib.dumps(self.info))

    def test_unconfigured_repository_stops_before_external_commands(self):
        self.config["github_repository"] = ""
        self.config_path.write_text(json.dumps(self.config))
        with self.assertRaisesRegex(ValueError, "not configured"):
            release.assets()
        self.assertEqual(self.commands, [])

    def test_changed_bundle_version_requires_rebuild(self):
        info = dict(self.info, CFBundleVersion="24")
        (self.root / "Info.plist").write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "Rebuild first"):
            release.assets()

    def test_wrong_key_cannot_issue_an_update(self):
        self.info["SUPublicEDKey"] = "different-public-key"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "does not match the public key"):
            release.assets()

    def test_old_source_commit_requires_rebuild(self):
        self.info["GitCommitHash"] = "old-commit"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "different source commit"):
            release.assets()

    def test_existing_or_lower_build_cannot_enter_feed(self):
        for previous in (23, 24):
            with self.subTest(previous=previous):
                (self.root / "appcast.xml").write_text(f'<rss xmlns:sparkle="{release.SPARKLE}"><channel><item><sparkle:version>{previous}</sparkle:version></item></channel></rss>')
                with self.assertRaisesRegex(ValueError, "Build number must exceed"):
                    release.assets()

    def test_feed_and_cask_reference_same_archive_and_preserve_history(self):
        (self.root / "appcast.xml").write_text(f'<rss xmlns:sparkle="{release.SPARKLE}"><channel><item><sparkle:version>22</sparkle:version></item></channel></rss>')
        release.assets()
        out = self.root / "build/release/1.1.15"
        items = ET.parse(out / "appcast.xml").findall("channel/item")
        self.assertEqual(len(items), 2)
        enclosure = items[0].find("enclosure")
        self.assertEqual(enclosure.attrib["length"], "11")
        self.assertEqual(enclosure.attrib[f"{{{release.SPARKLE}}}edSignature"], "signature")
        manifest = json.loads((out / "manifest.json").read_text())
        cask = (out / "Casks/maccelerate.rb").read_text()
        self.assertIn(manifest["sha256"], cask)
        self.assertTrue(manifest["dirty"])
        self.assertFalse((out / "Maccelerate-1.1.15-source.zip").exists())
        with self.assertRaisesRegex(ValueError, "cannot be published|Commit the intended source"):
            release.checked_candidate("1.1.15")

    def test_candidate_metadata_is_not_overwritten(self):
        release.assets()
        with self.assertRaisesRegex(ValueError, "already exists"):
            release.assets()

    def test_modified_candidate_is_rejected_before_github_write(self):
        release.assets()
        out = self.root / "build/release/1.1.15"
        manifest_path = out / "manifest.json"
        data = json.loads(manifest_path.read_text())
        data["dirty"] = False
        manifest_path.write_text(json.dumps(data))
        def clean_run(*args):
            if args[:3] == ("git", "rev-parse", "HEAD"): return "test-commit"
            return ""
        with patch.object(release, "run", side_effect=clean_run):
            (out / "appcast.xml").write_text("tampered-feed")
            with self.assertRaisesRegex(ValueError, "Candidate file changed"):
                release.checked_candidate("1.1.15")


if __name__ == "__main__":
    unittest.main()
