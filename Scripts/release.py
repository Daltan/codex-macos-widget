#!/usr/bin/env python3
"""Version, build, publish and verify a release using git and gh (no browser)."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
REPO = "Daltan/codex-macos-widget"
PLISTS = ("Config/App-Info.plist", "Config/Widget-Info.plist")


def run(*args, cwd=ROOT, log=None):
    if log:
        with Path(log).open("w") as stream:
            result = subprocess.run(args, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
        if result.returncode:
            raise RuntimeError(f"Command failed: {' '.join(args)}\nLog: {log}\n" + Path(log).read_text()[-6000:])
        return ""
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def git(*args):
    return run("git", *args)


def push(*args):
    # Per-command credentials; do not change global git or Codex configuration.
    return git("-c", "credential.helper=", "-c", "credential.helper=!gh auth git-credential", "push", "origin", *args)


def gh(*args):
    return run("gh", *args, "--repo", REPO)


def version_tuple(value):
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", value):
        raise ValueError(f"Invalid version: {value}")
    parts = [int(part) for part in value.split(".")]
    return tuple(parts + [0] * (3 - len(parts)))


def bump_version(value, bump):
    parts = list(version_tuple(value))
    index = {"major": 0, "minor": 1, "patch": 2}[bump]
    parts[index] += 1
    for position in range(index + 1, 3):
        parts[position] = 0
    return ".".join(map(str, parts))


def versions(root=ROOT):
    values = []
    for name in PLISTS:
        data = plistlib.loads((root / name).read_bytes())
        values.append((data["CFBundleShortVersionString"], int(data["CFBundleVersion"])))
    if values[0] != values[1]:
        raise RuntimeError("App and widget versions do not match")
    version_tuple(values[0][0])
    return values[0]


def preflight():
    if git("branch", "--show-current") != "main":
        raise RuntimeError("Release from main only")
    if git("status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("Commit tracked changes before releasing; never auto-stage unrelated work")
    remote = git("remote", "get-url", "origin")
    if remote not in (f"https://github.com/{REPO}.git", f"git@github.com:{REPO}.git", f"https://github.com/{REPO}"):
        raise RuntimeError(f"Unexpected origin: {remote}")
    run("gh", "auth", "status", "--hostname", "github.com")
    git("fetch", "origin", "main", "--tags")
    git("merge-base", "--is-ancestor", "origin/main", "HEAD")
    if not Path(os.environ.get("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")).is_dir():
        raise RuntimeError("Full Xcode is required")
    print("Preflight passed; untracked files are excluded from the source archive.", flush=True)


def prepare(bump, notes):
    preflight()
    version, build = versions()
    candidate = bump_version(version, bump)
    tagged = [version_tuple(tag[1:]) for tag in git("tag", "--list").splitlines()
              if re.fullmatch(r"v\d+\.\d+\.\d+", tag)]
    if tagged and version_tuple(candidate) <= max(tagged):
        raise RuntimeError("Next version must be greater than all existing release tags")
    content = Path(notes).read_text().strip()
    if not content:
        raise RuntimeError("Release notes must not be empty")
    notes_path = ROOT / "Docs/ReleaseNotes" / f"v{candidate}.md"
    if notes_path.exists():
        raise RuntimeError("Release notes already exist; use publish to resume a prepared version")
    for name in PLISTS:
        path = ROOT / name
        text = path.read_text()
        for key, value in (("CFBundleShortVersionString", candidate), ("CFBundleVersion", str(build + 1))):
            pattern = rf"(<key>{key}</key>\s*<string>)[^<]+(</string>)"
            text, count = re.subn(pattern, lambda match: match[1] + value + match[2], text)
            if count != 1:
                raise RuntimeError(f"Expected one {key} in {name}")
        path.write_text(text)
    notes_path.parent.mkdir(parents=True, exist_ok=True)
    notes_path.write_text(content + "\n")
    git("diff", "--check")
    git("add", *PLISTS, str(notes_path.relative_to(ROOT)))
    git("commit", "--only", *PLISTS, str(notes_path.relative_to(ROOT)), "-m", f"Prepare v{candidate} release (build {build + 1})")
    print(f"Prepared v{candidate}, build {build + 1}. Resume with: python3 Scripts/release.py publish", flush=True)


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def artifact_names(version, build):
    base = f"Codex-Usage-{version}-{build}-universal"
    return [f"{base}.dmg", f"{base}.zip", "INSTALL.txt", "SHA256SUMS.txt"]


def check_hashes(directory, expected):
    actual = {p.name for p in directory.iterdir() if p.is_file()}
    if actual != set(expected):
        raise RuntimeError(f"Unexpected artifact set: {actual}")
    for name, sha in expected.items():
        if digest(directory / name) != sha:
            raise RuntimeError(f"Checksum mismatch: {name}; will not overwrite any release asset")


def verify_package(source, artifacts, version, build, scratch):
    name = f"Codex-Usage-{version}-{build}-universal"
    run("shasum", "-a", "256", "-c", "SHA256SUMS.txt", cwd=artifacts)
    extracted = scratch / "unzipped"
    run("ditto", "-x", "-k", str(artifacts / f"{name}.zip"), str(extracted))
    mount = scratch / "mounted"
    run("hdiutil", "attach", "-readonly", "-nobrowse", "-mountpoint", str(mount), str(artifacts / f"{name}.dmg"))
    try:
        for directory in (extracted, mount):
            app = directory / "Codex Usage.app"
            run("codesign", "--verify", "--deep", "--strict", str(app))
            for bundle in (app, app / "Contents/PlugIns/CodexUsageWidget.appex"):
                info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
                if (info["CFBundleShortVersionString"], int(info["CFBundleVersion"])) != (version, build):
                    raise RuntimeError("Packaged bundle version mismatch")
            run("diff", "-qr", str(app), str(source / ".build/DerivedData/Build/Products/Release/Codex Usage.app"))
        if not (mount / "Applications").is_symlink() or (mount / "INSTALL.txt").read_bytes() != (artifacts / "INSTALL.txt").read_bytes():
            raise RuntimeError("Invalid DMG installation contents")
    finally:
        run("hdiutil", "detach", str(mount))


def build_artifacts(state_dir, version, build, sha):
    manifest_path = state_dir / "manifest.json"
    artifacts = state_dir / "assets"
    if manifest_path.exists():
        manifest = json.loads(manifest_path.read_text())
        if (manifest["commit"], manifest["version"], manifest["build"]) != (sha, version, build):
            raise RuntimeError("Prepared release source changed; do not rebuild/replace a pending release under the same tag")
        if set(manifest["sha256"]) != set(artifact_names(version, build)):
            raise RuntimeError("Invalid saved artifact manifest")
        check_hashes(artifacts, manifest["sha256"])
        print("Reusing verified artifacts for the same commit.", flush=True)
        return manifest
    state_dir.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="source-", dir=state_dir) as temporary:
        scratch = Path(temporary)
        source = scratch / "source"
        source.mkdir()
        run("git", "archive", "--format=tar", "-o", str(scratch / "source.tar"), sha)
        run("tar", "-xf", str(scratch / "source.tar"), "-C", str(source))
        run("python3", "Scripts/scan-secrets.py", cwd=ROOT, log=state_dir / "secrets.log")
        run("python3", "-m", "unittest", "discover", "-s", "Scripts/tests", cwd=source, log=state_dir / "workflow-tests.log")
        os.environ.setdefault("DEVELOPER_DIR", "/Applications/Xcode.app/Contents/Developer")
        run("swift", "test", cwd=source, log=state_dir / "swift-tests.log")
        run("bash", "Scripts/build.sh", cwd=source, log=state_dir / "build.log")
        package = source / ".build/releases" / f"Codex-Usage-{version}-{build}-universal"
        verify_package(source, package, version, build, scratch)
        artifacts.mkdir(exist_ok=True)
        for name in artifact_names(version, build):
            shutil.copy2(package / name, artifacts / name)
    manifest = {"commit": sha, "version": version, "build": build,
                "sha256": {name: digest(artifacts / name) for name in artifact_names(version, build)}}
    check_hashes(artifacts, manifest["sha256"])
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def release_info(tag):
    releases = json.loads(gh("release", "list", "--limit", "1000", "--json", "tagName"))
    if not any(item["tagName"] == tag for item in releases):
        return None
    return json.loads(gh("release", "view", tag, "--json", "isDraft,assets,url,tagName"))


def verify_downloads(tag, manifest, state_dir, public=False):
    with tempfile.TemporaryDirectory(prefix="download-", dir=state_dir) as temporary:
        destination = Path(temporary)
        if public:
            for name in manifest["sha256"]:
                url = f"https://github.com/{REPO}/releases/download/{tag}/{name}"
                with urllib.request.urlopen(url, timeout=60) as response:
                    (destination / name).write_bytes(response.read())
        else:
            gh("release", "download", tag, "--dir", str(destination))
        check_hashes(destination, manifest["sha256"])
        run("shasum", "-a", "256", "-c", "SHA256SUMS.txt", cwd=destination)


def ensure_tag(tag, sha):
    local = git("tag", "--list", tag)
    if local and git("rev-parse", f"{tag}^{{commit}}") != sha:
        raise RuntimeError(f"{tag} already points to a different commit")
    if not local:
        git("tag", "-a", tag, sha, "-m", f"Codex Usage {tag}")
    push(f"refs/tags/{tag}")
    remote = git("ls-remote", "origin", f"refs/tags/{tag}", f"refs/tags/{tag}^{{}}")
    if not any(line.startswith(sha + "\t") for line in remote.splitlines()):
        raise RuntimeError("Remote tag does not resolve to the built commit")


def publish():
    preflight()
    version, build = versions()
    if len(version.split(".")) != 3:
        raise RuntimeError("Run prepare first to set a three-component release version")
    tag, sha = f"v{version}", git("rev-parse", "HEAD")
    notes = ROOT / "Docs/ReleaseNotes" / f"{tag}.md"
    if not notes.is_file() or not notes.read_text().strip():
        raise RuntimeError(f"Missing release notes: {notes}")
    state_dir = ROOT / ".build/release-loop" / tag
    manifest = build_artifacts(state_dir, version, build, sha)
    if git("rev-parse", "HEAD") != sha or git("status", "--porcelain", "--untracked-files=no"):
        raise RuntimeError("Source changed during build; refusing to publish")
    push("main")
    ensure_tag(tag, sha)
    info = release_info(tag)
    if info is None:
        release_notes = state_dir / "release-notes.md"
        release_notes.write_text(notes.read_text() + f"\n\nSource: `{sha}` · Build: `{build}`\n\n"
                                 "macOS 14+ · Apple Silicon / Intel Universal. Download DMG or ZIP; no Xcode required.\n\n"
                                 "Ad-hoc signed, not Apple-notarized. Other-Mac first launch and Intel hardware remain unverified. "
                                 "See INSTALL.txt for installation and SHA256SUMS.txt for checksums.\n\n"
                                 "临时签名，未经 Apple 公证；其他 Mac 首次安装、Intel 实机仍未验证。安装方式见 INSTALL.txt。\n")
        gh("release", "create", tag, "--verify-tag", "--draft", "--title", f"Codex Usage {tag}", "--notes-file", str(release_notes))
        info = release_info(tag)
    existing = {asset["name"] for asset in info["assets"]}
    if existing - set(manifest["sha256"]):
        raise RuntimeError("Unexpected remote assets; refusing to modify the release")
    # Never replace uploaded bytes. Verify each existing asset before resuming.
    if existing:
        with tempfile.TemporaryDirectory(prefix="existing-", dir=state_dir) as temporary:
            for name in existing:
                gh("release", "download", tag, "--pattern", name, "--dir", temporary)
            check_hashes(Path(temporary), {name: manifest["sha256"][name] for name in existing})
    missing = set(manifest["sha256"]) - existing
    if missing and not info["isDraft"]:
        raise RuntimeError("Published release is incomplete; do not mutate published assets")
    for name in sorted(missing):
        gh("release", "upload", tag, str(state_dir / "assets" / name))
    verify_downloads(tag, manifest, state_dir)
    if info["isDraft"]:
        gh("release", "edit", tag, "--draft=false", "--latest", "--verify-tag")
    info = release_info(tag)
    if info["isDraft"] or {asset["name"] for asset in info["assets"]} != set(manifest["sha256"]):
        raise RuntimeError("Release publication/readback failed")
    verify_downloads(tag, manifest, state_dir, public=True)
    receipt = dict(manifest, tag=tag, url=info["url"], published=True, anonymous_downloads_verified=True)
    (state_dir / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Verified published release: {info['url']}\nReceipt: {state_dir / 'receipt.json'}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("run", "prepare"):
        command = commands.add_parser(name)
        command.add_argument("--bump", choices=["patch", "minor", "major"], default="patch")
        command.add_argument("--notes-file", type=Path, required=True)
    commands.add_parser("publish", help="Resume current prepared version without bumping or replacing assets")
    commands.add_parser("plan", help="Read local versions without changing files or remote state")
    args = parser.parse_args()
    if args.command == "plan":
        version, build = versions()
        print(json.dumps({"current": version, "build": build, "next": {b: bump_version(version, b) for b in ["patch", "minor", "major"]}}, indent=2))
        return
    (ROOT / ".build").mkdir(exist_ok=True)
    with (ROOT / ".build/release-loop.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError("Another release process is already running") from error
        if args.command in ("run", "prepare"):
            prepare(args.bump, args.notes_file)
        if args.command in ("run", "publish"):
            publish()


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release stopped: {error}\nPreserve .build/release-loop and resume with 'python3 Scripts/release.py publish' after fixing the cause. No tags or assets are force-replaced.", file=sys.stderr)
        sys.exit(1)
