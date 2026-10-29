#!/usr/bin/env python3
"""Bound Bgmori-owned development artifacts; default to a read-only preview."""

import argparse
import fcntl
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import time

GIB = 1024 ** 3
DAY = 86400
UI_MARKER = ".bgmori-ui-run"
TEMP_MARKER = ".bgmori-temporary"


def safe_path(path, root):
    """Reject links in the root or ancestors, rather than resolving outside it."""
    path, root = Path(path).absolute(), Path(root).absolute()
    if root.resolve() != root or path == root or root not in path.parents:
        raise ValueError(f"Refusing cleanup outside its owned root: {path}")
    current = path
    while current != root:
        if current.is_symlink():
            raise ValueError(f"Refusing symlink cleanup: {current}")
        current = current.parent
    return path


def allocated_size(path):
    total = path.lstat().st_blocks * 512
    if path.is_dir() and not path.is_symlink():
        for directory, _, files in os.walk(path, followlinks=False):
            for name in files:
                total += (Path(directory) / name).lstat().st_blocks * 512
    return total


def active(path):
    marker = path / ".active"
    if not marker.exists():
        return False
    try:
        pid = int(marker.read_text().strip())
        if pid <= 0:
            return True
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except (ValueError, OSError):
        # An unreadable owner is not evidence that the job has finished.
        return True


def retention(paths, *, count, budget=None, age=None, now=None):
    now = time.time() if now is None else now
    kept, used, expired = 0, 0, []
    for path in sorted(paths, key=lambda p: (p.stat().st_mtime, p.name), reverse=True):
        if active(path):
            continue
        size = allocated_size(path)
        old = age is not None and now - path.stat().st_mtime > age
        if old or kept >= count or (budget is not None and used + size > budget):
            expired.append(path)
        else:
            kept += 1
            used += size
    return expired


def owned_directories(root, marker):
    if not root.exists():
        return []
    safe_path(root / ".ownership-check", root)
    return [safe_path(p, root) for p in root.iterdir()
            if not p.is_symlink() and p.is_dir()
            and (p / marker).is_file() and not (p / marker).is_symlink()]


def backup_directories(root):
    if not root.exists():
        return []
    safe_path(root / ".ownership-check", root)
    result = []
    for path in root.iterdir():
        if not re.fullmatch(r"\d{8}-\d{6}\.[A-Za-z0-9]+", path.name):
            continue
        if path.is_symlink() or not path.is_dir():
            continue
        info = path / "Bgmori.app/Contents/Info.plist"
        safe_path(info, root)
        try:
            with info.open("rb") as stream:
                if plistlib.load(stream).get("CFBundleIdentifier") == "com.yaron.bgmori":
                    result.append(path)
        except (OSError, ValueError, plistlib.InvalidFileException):
            continue
    return result


def builds_running():
    output = subprocess.run(["ps", "-axo", "comm"], check=True,
                            capture_output=True, text=True).stdout
    return any(Path(line.strip()).name in {"xcodebuild", "swift-frontend", "clang", "go"}
               for line in output.splitlines())


def plan(repo, backups, busy):
    build = repo / "build"
    actions = []
    reports = build / "ui-results"
    actions += [(p, reports, "UI reports: 3 runs / 1 GiB / 7 days") for p in
                retention(owned_directories(reports, UI_MARKER), count=3, budget=GIB, age=7 * DAY)]
    # Prune only recognisable Bgmori app backups, after a valid installation exists.
    installed = Path("/Applications/Bgmori.app/Contents/Info.plist")
    try:
        with installed.open("rb") as stream:
            valid_installation = plistlib.load(stream).get("CFBundleIdentifier") == "com.yaron.bgmori"
    except (OSError, ValueError, plistlib.InvalidFileException):
        valid_installation = False
    if valid_installation:
        actions += [(p, backups, "Mac backups: newest 2") for p in
                    retention(backup_directories(backups), count=2)]
    if not busy:
        temp = build / "tmp"
        actions += [(p, temp, "Abandoned temporary work: 7 days") for p in
                    retention(owned_directories(temp, TEMP_MARKER), count=100000, age=7 * DAY)]
        caches = [safe_path(build / name, build) for name in ("DerivedData-ios", "DerivedData-mac")
                  if (build / name).exists()]
        total = sum(allocated_size(p) for p in caches)
        for path in sorted(caches, key=lambda p: p.stat().st_mtime):
            if total <= 4 * GIB:
                break
            if active(path):
                continue
            total -= allocated_size(path)
            actions.append((path, build, "Build caches: combined 4 GiB"))
    return actions


def apply_actions(actions, repo, apply):
    for path, root, reason in actions:
        safe_path(path, root)
        if active(path):
            continue
        if repo in path.parents:
            tracked = subprocess.run(["git", "-C", str(repo), "ls-files", "--", str(path)],
                                     check=True, capture_output=True, text=True).stdout
            if tracked:
                raise ValueError(f"Refusing to remove tracked files: {path}")
        print(f"{'DELETE' if apply else 'WOULD DELETE'} {allocated_size(path) / GIB:.3f} GiB {path} ({reason})")
        if apply:
            shutil.rmtree(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Permanently remove expired generated artifacts")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[1]
    build = repo / "build"
    backups = Path.home() / "Library/Application Support/Bgmori/BuildBackups"
    # Retention is attached to developer commands, not a background service.
    lock = None
    if args.apply:
        safe_path(build / ".maintenance.lock", build)
        build.mkdir(exist_ok=True)
        lock_path = safe_path(build / ".maintenance.lock", build)
        lock = lock_path.open("a")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Storage maintenance already running; skipped.")
            return
    busy = builds_running()
    actions = plan(repo, backups, busy)
    apply_actions(actions, repo, args.apply)
    if not actions:
        print("Development storage is within retention limits.")
    if busy:
        print("Active build detected; build caches and temporary work were preserved.")
    if lock:
        lock.close()


if __name__ == "__main__":
    main()
