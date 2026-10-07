#!/usr/bin/env python3
"""Check actual leak paths: extra source, excluded code, history and archives."""
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location("boundary", pathlib.Path(__file__).resolve().parents[1] / "dist/public_boundary.py")
boundary = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boundary)


class PublicBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = pathlib.Path(self.temp.name)
        (self.root / "dist").mkdir()
        (self.root / "Sources").mkdir()
        self.files = ["dist/public-files.json", ".public-free-repository", "Sources/Core.swift"]
        (self.root / "dist/public-files.json").write_text(json.dumps(self.files))
        (self.root / ".public-free-repository").write_text("free")
        (self.root / "Sources/Core.swift").write_text("let switching = true\n")

    def test_extra_source_is_rejected(self):
        (self.root / "Sources/Extra.swift").write_text("private code")
        with self.assertRaisesRegex(ValueError, "Unreviewed source"):
            boundary.audit_sources(self.root)

    def test_reviewed_appearance_and_statistics_are_allowed(self):
        (self.root / "Sources/Core.swift").write_text(
            "final class StatisticsStore {}\nfinal class AppearanceSettingsViewController {}\n"
            "final class OSDWindow {}\nlet statisticsEnabled = true\n")
        boundary.audit_sources(self.root)

    def test_code_hidden_in_reviewed_file_is_rejected(self):
        (self.root / "Sources/Core.swift").write_text("final class SupportWindowController {}")
        with self.assertRaisesRegex(ValueError, "Excluded implementation"):
            boundary.audit_sources(self.root)

    def test_symlink_outside_checkout_is_rejected(self):
        source = self.root / "Sources/Core.swift"
        source.unlink()
        source.symlink_to(self.root.parent / "secret.swift")
        with self.assertRaisesRegex(ValueError, "linked"):
            boundary.audit_sources(self.root)

    def test_removed_code_in_old_commit_is_rejected(self):
        def git(*args):
            subprocess.run(["git", *args], cwd=self.root, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        git("init", "--initial-branch=main")
        git("config", "user.name", "Boundary test")
        git("config", "user.email", "boundary@example.invalid")
        source = self.root / "Sources/Core.swift"
        source.write_text("final class SupportWindowController {}")
        git("add", ".")
        git("commit", "-m", "old private code")
        source.write_text("let switching = true\n")
        git("add", ".")
        git("commit", "-m", "remove private code")
        with self.assertRaisesRegex(ValueError, "Excluded implementation"):
            boundary.audit_history(self.root)

    def test_source_zip_rejects_an_extra_file(self):
        path = self.root / "source.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name in self.files:
                archive.write(self.root / name, "Free/" + name)
            archive.writestr("Free/private/code.swift", "private code")
        with self.assertRaisesRegex(ValueError, "inventory"):
            boundary.audit_archive(path, "Free/", self.root)

    def test_local_configuration_and_key_backups_cannot_enter_inventory(self):
        for name in ("dist/release-config.local.json", ".env.local", "backup.enc"):
            with self.subTest(name=name):
                (self.root / "dist/public-files.json").write_text(json.dumps(self.files + [name]))
                with self.assertRaisesRegex(ValueError, "Unsafe public path"):
                    boundary.public_files(self.root)

    def test_public_config_cannot_contain_local_signing_settings(self):
        self.files.append("dist/release-config.json")
        (self.root / "dist/public-files.json").write_text(json.dumps(self.files))
        config = self.root / "dist/release-config.json"
        config.write_text(json.dumps({"signing_identity": "Developer ID Application: Test (TEAM)"}))
        with self.assertRaisesRegex(ValueError, "local signing settings"):
            boundary.audit_sources(self.root)
        config.write_text(json.dumps({"signing_identity": "", "notary_profile": "", "sparkle_account": ""}))
        boundary.audit_sources(self.root)

    def test_credentials_are_rejected_even_in_validator_test_files(self):
        samples = [
            b"github_pat_" + b"A" * 50,
            b"ghp_" + b"B" * 40,
            b"-----BEGIN " + b"PRIVATE KEY-----",
            b"-".join([b"abcd", b"efgh", b"ijkl", b"mnop"]),
        ]
        for data in samples:
            with self.subTest(data_type=data[:8]):
                with self.assertRaisesRegex(ValueError, "Private credential"):
                    boundary.inspect_content("diagnostics/test-public-boundary.py", data)

    def test_local_paths_are_rejected_in_sources_and_binary_payloads(self):
        paths = [b"/" + b"Users/tester/project/main.c", b"/private/var/" + b"folders/cache/file", b"C:" + bytes([92]) + b"Users" + bytes([92]) + b"tester"]
        for path in paths:
            for metadata in (True, False):
                with self.subTest(path=path, metadata=metadata):
                    with self.assertRaisesRegex(ValueError, "Local machine path"):
                        boundary.inspect_content("Maccelerate", b"binary-prefix" + path + b"\0", metadata=metadata)

    def test_internal_release_metadata_is_rejected_but_public_key_is_allowed(self):
        certificate = b"Developer ID Application: Example (" + b"A" * 10 + b")"
        narrative = b"The user " + b"approved the candidate"
        for text in (certificate, narrative):
            with self.assertRaisesRegex(ValueError, "Internal publication metadata"):
                boundary.inspect_content("release-notes.md", text)
        boundary.inspect_content("Info.plist", b"SUPublicEDKey public-key; SUFeedURL https://example.invalid/feed")
        # The public signer certificate is an intentional part of signed binaries.
        boundary.inspect_content("Maccelerate", certificate, metadata=False)

    def test_archive_checks_local_configuration_values(self):
        self.files.append("dist/release-config.json")
        (self.root / "dist/public-files.json").write_text(json.dumps(self.files))
        (self.root / "dist/release-config.json").write_text(json.dumps({"notary_profile": "internal-profile"}))
        path = self.root / "source.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name in self.files:
                archive.write(self.root / name, "Free/" + name)
        with self.assertRaisesRegex(ValueError, "local signing settings"):
            boundary.audit_archive(path, "Free/", self.root)

    def test_legacy_metadata_exception_does_not_permit_future_metadata(self):
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=self.root, stderr=subprocess.DEVNULL).decode().strip()
        git("init", "--initial-branch=main")
        git("config", "user.name", "Boundary test")
        git("config", "user.email", "boundary@example.invalid")
        source = self.root / "Sources/Core.swift"
        source.write_bytes(b"// The user " + b"approved this historical draft\n")
        git("add", ".")
        git("commit", "-m", "historical public draft")
        legacy = git("rev-parse", "HEAD")
        source.write_text("let switching = true\n")
        git("add", ".")
        git("commit", "-m", "clean metadata")
        with patch.object(boundary, "LEGACY_METADATA_COMMIT", legacy):
            boundary.audit_history(self.root)
            with self.assertRaisesRegex(ValueError, "Internal publication metadata"):
                boundary.audit_history(self.root, strict_metadata=True)
            git("commit", "--allow-empty", "-m", "The user " + "approved another draft")
            with self.assertRaisesRegex(ValueError, "Internal publication metadata"):
                boundary.audit_history(self.root)

    def test_valid_source_zip_passes(self):
        path = self.root / "source.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name in self.files:
                archive.write(self.root / name, "Free/" + name)
        boundary.audit_archive(path, "Free/", self.root)


if __name__ == "__main__":
    unittest.main()
