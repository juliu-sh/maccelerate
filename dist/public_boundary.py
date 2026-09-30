#!/usr/bin/env python3
"""Validate the public Free inventory, Git history, source ZIP and app binaries."""
import argparse
import json
import pathlib
import re
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
INVENTORY = "dist/public-files.json"
MARKER = ".public-free-repository"
# Identifiers of excluded implementations, not a list of optional feature flags.
EXCLUDED = re.compile(rb"StatisticsStore|StatisticsModel|StatisticsAccumulator|ISSStatistic|iss_statistics_|statisticsSnapshot|statistics_record|statisticsEnabled|AppearanceSettingsViewController|SpaceHUDView|OSDWindow|SupportMilestones|SupportWindowController|localStatisticsV1|showOSD|osdDurationMs")
PRIVATE_KEY = re.compile(
    rb"-----BEGIN (?:[A-Z ]*PRIVATE KEY)-----|gh[pousr]_[A-Za-z0-9]{30,}"
    rb"|github_pat_[A-Za-z0-9_]{40,}|AKIA[A-Z0-9]{16}"
    rb"|sk_live_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{20,}"
    rb"|\b[a-z]{4}(?:-[a-z]{4}){3}\b"
)
LOCAL_PATH = re.compile(rb"/" rb"Users/[^/\s\x00]+/|/private/var/" rb"folders/|[A-Za-z]:\\Users\\")
PERSONAL_CERTIFICATE = re.compile(rb"Developer ID Application: [^\r\n\"<>]{1,120}\([A-Z0-9]{10}\)")
INTERNAL_NARRATIVE = re.compile(rb"(?i)the user (?:approved|confirmed|reported)|user-reported|exact build and hardware were not supplied")
LOCAL_CONFIG_FIELDS = {"signing_identity", "notary_profile", "sparkle_account"}
# Previously published nonsecret settings are grandfathered only in ancestors of
# this fixed cleanup commit. New history, current files and archives are strict.
# This exemption never permits credentials, local paths or excluded code.
LEGACY_METADATA_COMMIT = "59e94776a52cb87f99e27ab51d6622cca82de99c"


def public_files(root=ROOT):
    files = json.loads((root / INVENTORY).read_text())
    if not isinstance(files, list) or len(files) != len(set(files)):
        raise ValueError("Invalid public file inventory")
    for name in files:
        p = pathlib.PurePosixPath(name)
        if p.is_absolute() or ".." in p.parts or p.name == ".DS_Store" or p.suffix in {".p12", ".p8", ".key", ".pem", ".dmg", ".zip", ".enc"} or p.name.startswith(".env") or p.name.endswith(".local.json"):
            raise ValueError(f"Unsafe public path: {name}")
    return files


def inspect_content(name, data, *, metadata=True):
    # The validator and its tests necessarily contain excluded identifiers.
    fixtures = {"dist/public_boundary.py", "diagnostics/test-public-boundary.py"}
    if name not in fixtures and EXCLUDED.search(data):
        raise ValueError(f"Excluded implementation found: {name}")
    if PRIVATE_KEY.search(data):
        raise ValueError(f"Private credential found: {name}")
    if LOCAL_PATH.search(data):
        raise ValueError(f"Local machine path found: {name}")
    if metadata and name not in fixtures:
        if PERSONAL_CERTIFICATE.search(data) or INTERNAL_NARRATIVE.search(data):
            raise ValueError(f"Internal publication metadata found: {name}")
        if name == "dist/release-config.json":
            settings = json.loads(data)
            if any(settings.get(key) for key in LOCAL_CONFIG_FIELDS):
                raise ValueError("Keep local signing settings in ignored dist/release-config.local.json")


def audit_text(path):
    inspect_content(path.name, path.read_bytes())


def audit_sources(root=ROOT):
    files = public_files(root)
    for name in files:
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Missing or linked public file: {name}")
        inspect_content(name, path.read_bytes())
    expected = set(files)
    for folder in ("Sources", "Tests"):
        for path in (root / folder).rglob("*"):
            if path.name == ".DS_Store":
                continue
            if path.is_symlink():
                raise ValueError(f"Linked source path: {path.relative_to(root)}")
            if path.is_file() and str(path.relative_to(root)) not in expected:
                raise ValueError(f"Unreviewed source file: {path.relative_to(root)}")
    return files


def git(root, *args):
    return subprocess.check_output(["git", *args], cwd=root)


def audit_history(root=ROOT, strict_metadata=False):
    files = set(audit_sources(root))
    if not (root / MARKER).is_file():
        raise ValueError("Use the exported public Free checkout; no public marker found")
    commits = git(root, "rev-list", "--all").decode().splitlines()
    if not commits:
        raise ValueError("Commit the reviewed Free source first")
    head_files = set(filter(None, git(root, "ls-tree", "-r", "--name-only", "-z", "HEAD").decode().split("\0")))
    if head_files != files:
        raise ValueError("The committed Free source does not match the public inventory")
    legacy = set()
    if not strict_metadata:
        result = subprocess.run(["git", "rev-list", LEGACY_METADATA_COMMIT], cwd=root,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if result.returncode == 0:
            legacy = set(result.stdout.decode().splitlines())
    for commit in commits:
        inspect_content("commit metadata", git(root, "show", "-s", "--format=%B", commit), metadata=commit not in legacy)
        names = git(root, "ls-tree", "-r", "--name-only", "-z", commit).decode().split("\0")
        for name in filter(None, names):
            if name not in files:
                raise ValueError(f"Unreviewed file in Git history: {name}")
            mode = git(root, "ls-tree", commit, "--", name).decode().split()[0]
            if mode not in {"100644", "100755"}:
                raise ValueError(f"Linked or embedded repository in Git history: {name}")
            inspect_content(name, git(root, "show", f"{commit}:{name}"), metadata=commit not in legacy)
    return len(commits)


def audit_archive(path, prefix, root=ROOT):
    expected = {prefix + name for name in public_files(root)}
    with zipfile.ZipFile(path) as archive:
        members = [item for item in archive.infolist() if not item.is_dir()]
        if len(members) != len(expected) or {item.filename for item in members} != expected:
            raise ValueError("Source ZIP does not match the public inventory")
        for item in members:
            if (item.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError("Source ZIP contains a symbolic link")
            inspect_content(item.filename.removeprefix(prefix), archive.read(item))


def audit_app(app):
    import plistlib
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("MaccelerateEdition") != "free":
        raise ValueError("Expected the Free edition")
    # Inspect only our executables; third-party frameworks are independently licensed.
    for name in ("Maccelerate", "ISSCli"):
        inspect_content(name, (app / "Contents/MacOS" / name).read_bytes(), metadata=False)
    for path in (app / "Contents/Resources").rglob("*"):
        if path.is_file():
            inspect_content(str(path.relative_to(app)), path.read_bytes())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--history", action="store_true")
    parser.add_argument("--app", type=pathlib.Path)
    parser.add_argument("--strict-history", action="store_true", help="Also reject previously published nonsecret metadata")
    parser.add_argument("--text", type=pathlib.Path, help="Check release notes or another publication text")
    args = parser.parse_args()
    files = audit_sources()
    print(f"Public Free source validated: {len(files)} files")
    if args.history or args.strict_history:
        print(f"Public Git history validated: {audit_history(strict_metadata=args.strict_history)} commits")
    if args.text:
        audit_text(args.text)
        print("Publication text validated")
    if args.app:
        audit_app(args.app)
        print("Free executables and resources validated")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
