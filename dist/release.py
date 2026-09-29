#!/usr/bin/env python3
"""Local release metadata and explicit GitHub release operations. No credentials in files."""
import argparse
import datetime
import email.utils
import hashlib
import json
import pathlib
import plistlib
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "dist"))
import public_boundary
CONFIG = ROOT / "dist/release-config.json"
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def run(*args):
    return subprocess.check_output([str(a) for a in args], cwd=ROOT, text=True).strip()


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else hashlib.sha256(stream.read()).hexdigest()


def config(require_repo=False):
    data = json.loads(CONFIG.read_text())
    if require_repo:
        for key in ("github_repository", "homebrew_repository"):
            if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", data[key]):
                raise ValueError("GitHub repositories are not configured. Run dist/release.py configure first.")
    return data


def assets():
    cfg = config(True)
    public_boundary.audit_history(ROOT)
    app = ROOT / "build/Maccelerate.app"
    public_boundary.audit_app(app)
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if info.get("MaccelerateBuildChannel") != "official" or info.get("MaccelerateEdition") != "free":
        raise ValueError("Release assets require an official Free build.")
    if info.get("GitCommitHash") != run("git", "rev-parse", "--short", "HEAD"):
        raise ValueError("Rebuild first: app was built from a different source commit.")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or not build.isdigit():
        raise ValueError("Expected a three-part version and integer build number.")
    with (ROOT / "Info.plist").open("rb") as stream:
        source_info = plistlib.load(stream)
    for key in ("CFBundleShortVersionString", "CFBundleVersion", "SUPublicEDKey", "SUFeedURL"):
        if info[key] != source_info[key]:
            raise ValueError(f"Rebuild first: bundle {key} differs from source.")
    if info["SUFeedURL"] != cfg["feed_url"]:
        raise ValueError("The configured feed URL differs from the built app.")
    run("codesign", "--verify", "--deep", "--strict", app)
    signing_key = run(ROOT / "build/sparkle-tools/generate_keys", "--account", cfg["sparkle_account"], "-p")
    if signing_key != info["SUPublicEDKey"]:
        raise ValueError("The Sparkle Keychain key does not match the public key in the app.")
    dmg = ROOT / f"build/Maccelerate-{version}.dmg"
    run("xcrun", "stapler", "validate", dmg)
    out = ROOT / "build/release" / version
    if out.exists():
        raise ValueError(f"Release metadata already exists: {out}. Do not overwrite an issued version.")
    signature = run(ROOT / "build/sparkle-tools/sign_update", "--account", cfg["sparkle_account"], "-p", dmg)
    run(ROOT / "build/sparkle-tools/sign_update", "--account", cfg["sparkle_account"], "--verify", dmg, signature)
    tree = ET.parse(ROOT / "appcast.xml")
    channel = tree.find("channel")
    if channel is None:
        raise ValueError("Invalid appcast: missing channel.")
    for item in channel.findall("item"):
        enclosure = item.find("enclosure")
        prior = item.findtext(f"{{{SPARKLE}}}version")
        if prior is None and enclosure is not None:
            prior = enclosure.get(f"{{{SPARKLE}}}version")
        if prior is None or int(prior) >= int(build):
            raise ValueError("Build number must exceed every existing appcast build.")
    url = f"https://github.com/{cfg['github_repository']}/releases/download/v{version}/{dmg.name}"
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Maccelerate {version}"
    ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
    ET.SubElement(item, "description").text = f"Maccelerate {version}. See the release notes for changes."
    ET.SubElement(item, "link").text = f"https://github.com/{cfg['github_repository']}/releases/tag/v{version}"
    ET.SubElement(item, "enclosure", {"url": url, "type": "application/octet-stream", "length": str(dmg.stat().st_size), f"{{{SPARKLE}}}edSignature": signature})
    channel.insert(0, item)
    out.mkdir(parents=True)
    shutil.copy2(dmg, out / dmg.name)
    checksum = sha(dmg)
    (out / f"{dmg.name}.sha256").write_text(f"{checksum}  {dmg.name}\n")
    ET.indent(tree)
    tree.write(out / "appcast.xml", encoding="utf-8", xml_declaration=True)
    # A separate tap uses this file without changing the app's source repository.
    (out / "Casks").mkdir()
    (out / "Casks/maccelerate.rb").write_text(f'''cask "maccelerate" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/{cfg['github_repository']}/releases/download/v#{{version}}/Maccelerate-#{{version}}.dmg"
  name "Maccelerate"
  desc "Accelerate switching between Spaces"
  homepage "https://maccelerate.app/"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura

  app "Maccelerate.app"
end
''')
    dirty = bool(run("git", "status", "--porcelain"))
    commit = run("git", "rev-parse", "HEAD")
    if not dirty:
        source_paths = public_boundary.public_files(ROOT)
        run("git", "archive", "--format=zip", f"--prefix=Maccelerate-{version}/", "-o", out / f"Maccelerate-{version}-source.zip", "HEAD", *source_paths)
        public_boundary.audit_archive(out / f"Maccelerate-{version}-source.zip", f"Maccelerate-{version}/", ROOT)
    shutil.copy2(ROOT / "RELEASE_NOTES_DRAFT.md", out / "release-notes.md")
    manifest = {"version": version, "build": build, "commit": commit, "dirty": dirty, "edition": "free", "public_history_checked": True, "repository": cfg["github_repository"], "tap": cfg["homebrew_repository"], "dmg": dmg.name, "sha256": checksum, "signature": signature,
        "files": {str(path.relative_to(out)): sha(path) for path in out.rglob("*") if path.is_file()}}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"Prepared {out}; dirty={dirty}. Nothing published.")


def checked_candidate(version):
    cfg = config(True)
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid version.")
    out = ROOT / "build/release" / version
    data = json.loads((out / "manifest.json").read_text())
    if data["dirty"] or run("git", "status", "--porcelain"):
        raise ValueError("Commit the intended source and prepare a clean candidate before publishing.")
    public_boundary.audit_history(ROOT)
    if data.get("edition") != "free" or not data.get("public_history_checked"):
        raise ValueError("Candidate has not passed the public Free boundary check.")
    if run("git", "rev-parse", "HEAD") != data["commit"] or cfg["github_repository"] != data["repository"]:
        raise ValueError("Candidate does not match HEAD or configured repository.")
    if sha(out / data["dmg"]) != data["sha256"]:
        raise ValueError("The candidate DMG changed after signing.")
    for name, expected in data["files"].items():
        if sha(out / name) != expected:
            raise ValueError(f"Candidate file changed after preparation: {name}")
    run(ROOT / "build/sparkle-tools/sign_update", "--account", cfg["sparkle_account"], "--verify", out / data["dmg"], data["signature"])
    run("xcrun", "stapler", "validate", out / data["dmg"])
    public_boundary.audit_archive(out / f"Maccelerate-{version}-source.zip", f"Maccelerate-{version}/", ROOT)
    return out, data


def draft(version):
    out, data = checked_candidate(version)
    paths = [out / data["dmg"], out / f"{data['dmg']}.sha256", out / f"Maccelerate-{version}-source.zip", out / "appcast.xml"]
    run("gh", "release", "create", f"v{version}", *paths, "--repo", data["repository"], "--draft", "--target", data["commit"], "--title", f"Maccelerate {version}", "--notes-file", out / "release-notes.md")
    print("GitHub draft created. Review it and test installation before publishing.")


def publish(version):
    out, data = checked_candidate(version)
    # Check the draft asset itself before exposing it or changing the feed.
    check = out / "github-check"
    check.mkdir(exist_ok=True)
    run("gh", "release", "download", f"v{version}", "--repo", data["repository"], "--pattern", data["dmg"], "--dir", check, "--clobber")
    if sha(check / data["dmg"]) != data["sha256"]:
        raise ValueError("GitHub asset does not match the tested DMG.")
    run("gh", "release", "edit", f"v{version}", "--repo", data["repository"], "--draft=false", "--latest")
    print("Release published. Deploy this appcast to the configured HTTPS feed, then update the tap:")
    print(out / "appcast.xml")
    print(out / "Casks/maccelerate.rb")
    print("Copy the published appcast back to the source repository for the next release.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subs = parser.add_subparsers(dest="command", required=True)
    setup = subs.add_parser("configure")
    setup.add_argument("--repository", required=True)
    setup.add_argument("--tap", required=True)
    subs.add_parser("assets")
    subs.add_parser("check-config")
    for command in ("draft", "publish"):
        subs.add_parser(command).add_argument("version")
    args = parser.parse_args()
    if args.command == "configure":
        data = config()
        for value in (args.repository, args.tap):
            if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", value):
                raise ValueError("Use OWNER/REPOSITORY.")
        if not args.tap.split("/")[1].startswith("homebrew-"):
            raise ValueError("Name the tap repository homebrew-tap (or homebrew-NAME).")
        data.update(github_repository=args.repository, homebrew_repository=args.tap)
        CONFIG.write_text(json.dumps(data, indent=2) + "\n")
        print("GitHub destinations configured. No repository created or published.")
    elif args.command == "assets":
        assets()
    elif args.command == "check-config":
        config(True)
        print("Release destinations configured.")
    elif args.command == "draft":
        draft(args.version)
    else:
        publish(args.version)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
