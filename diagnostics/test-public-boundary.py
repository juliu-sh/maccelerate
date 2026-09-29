#!/usr/bin/env python3
"""Check actual leak paths: extra source, excluded code, history and archives."""
import importlib.util
import json
import pathlib
import subprocess
import tempfile
import unittest
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

    def test_code_hidden_in_reviewed_file_is_rejected(self):
        (self.root / "Sources/Core.swift").write_text("final class StatisticsStore {}")
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
        source.write_text("final class StatisticsStore {}")
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

    def test_valid_source_zip_passes(self):
        path = self.root / "source.zip"
        with zipfile.ZipFile(path, "w") as archive:
            for name in self.files:
                archive.write(self.root / name, "Free/" + name)
        boundary.audit_archive(path, "Free/", self.root)


if __name__ == "__main__":
    unittest.main()
