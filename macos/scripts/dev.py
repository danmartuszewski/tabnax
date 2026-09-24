#!/usr/bin/env python3
"""Build, safely replace, and reload the native development app. Standard library only."""

import argparse
import fcntl
import hashlib
import os
from pathlib import Path
import select
import shutil
import signal
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
WATCH_ROOTS = ("Tabnax", "Packages", "SafariCompanion", "BrowserCompanion", "Tabnax.xcodeproj")
IGNORED = {"build", ".build", ".git", "xcuserdata", "node_modules", "__pycache__"}


def snapshot(root=ROOT):
    """Content signatures include additions/removals, but ignore editor/build churn."""
    result = {}
    for name in WATCH_ROOTS:
        for directory, folders, files in os.walk(root / name):
            folders[:] = sorted(folder for folder in folders if folder not in IGNORED
                                and not folder.startswith(".")
                                and not (Path(directory) / folder).is_symlink())
            for name in sorted(files):
                path = Path(directory) / name
                if name.startswith(".") or name.endswith(("~", ".swp", ".swo", ".xcuserstate")) or path.is_symlink():
                    continue
                try:
                    result[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).digest()
                except FileNotFoundError:
                    pass  # An editor may replace a file atomically while we scan.
    return result


class Changes:
    """Remember the attempted source revision, including edits made during a build."""
    def __init__(self, initial):
        self.attempted = initial
        self.observed = initial
        self.changed_at = 0.0

    def ready(self, current, now):
        if current != self.observed:
            self.observed = current
            self.changed_at = now
        return current != self.attempted and now - self.changed_at >= 0.6

    def start(self):
        self.attempted = self.observed.copy()


class Runner:
    def __init__(self, root=ROOT):
        self.root = root
        self.work = root / "build/dev"
        self.derived = root / "build/DevDerivedData"
        self.app = self.work / "Tabnax.app"
        self.staged = self.work / ".Tabnax-next.app"
        self.backup = self.work / ".Tabnax-previous.app"
        self.helper = self.work / "dev-app"
        self.log = self.work / "build.log"
        self.work.mkdir(parents=True, exist_ok=True)

    def run(self, command, output):
        output.write("\n$ " + " ".join(map(str, command)) + "\n")
        output.flush()
        subprocess.run(list(map(str, command)), cwd=self.root, stdout=output,
                       stderr=subprocess.STDOUT, check=True)

    def launch(self, path, output):
        self.run(["/usr/bin/open", "-n", path, "--args", "--settings"], output)
        self.run([self.helper, "wait", path], output)

    def promote(self, output):
        # Deliver Ctrl-C after replacement/rollback, never with the app half moved.
        previous_mask = signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT})
        try:
            self.replace_app(output)
        finally:
            signal.pthread_sigmask(signal.SIG_SETMASK, previous_mask)

    def replace_app(self, output):
        managed = [self.app] + [self.root / "build/DerivedData/Build/Products" / config / "Tabnax.app"
                               for config in ("Debug", "Release")]
        stopped = subprocess.run([str(self.helper), "stop"] + list(map(str, managed)),
                                 text=True, stdout=subprocess.PIPE, stderr=output, check=True)
        previously_running = [Path(line) for line in stopped.stdout.splitlines() if line]
        if self.backup.exists():
            shutil.rmtree(self.backup)
        had_previous = self.app.exists()
        installed = False
        try:
            if had_previous:
                self.app.rename(self.backup)
            self.staged.rename(self.app)
            installed = True
            self.launch(self.app, output)
        except (OSError, subprocess.CalledProcessError):
            # Keep one known-good bundle so a failed replacement can be undone.
            if installed:
                self.run([self.helper, "stop", self.app], output)
                shutil.rmtree(self.app)
            if self.backup.exists():
                self.backup.rename(self.app)
            restore = self.app if had_previous else next(iter(previously_running), None)
            if restore is not None and restore.exists():
                self.launch(restore, output)
            raise

    def reload(self):
        print("Building Tabnax…", flush=True)
        try:
            with self.log.open("w") as output:
                source = self.root / "scripts/dev-app.swift"
                if not self.helper.exists() or source.stat().st_mtime_ns > self.helper.stat().st_mtime_ns:
                    self.run(["/usr/bin/xcrun", "swiftc", source, "-module-cache-path",
                              self.work / "ModuleCache", "-o", self.helper], output)
                self.run(["/usr/bin/xcodebuild", "-quiet", "-project", "Tabnax.xcodeproj", "-scheme", "Tabnax",
                          "-configuration", "Debug", "-destination", "platform=macOS,arch=arm64",
                          "-derivedDataPath", self.derived, "build"], output)
                product = self.derived / "Build/Products/Debug/Tabnax.app"
                if self.staged.exists():
                    shutil.rmtree(self.staged)
                self.run(["/usr/bin/ditto", product, self.staged], output)
                self.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", self.staged], output)
                self.promote(output)
        except (OSError, subprocess.CalledProcessError):
            print("Reload failed. Fix the error and save, or press r and Enter to retry.", flush=True)
            print("\n".join(self.log.read_text(errors="replace").splitlines()[-24:]))
            print("Full log: " + str(self.log), flush=True)
            return False
        print("Reloaded Tabnax. Settings are open; saved preferences are preserved.", flush=True)
        return True


def main():
    parser = argparse.ArgumentParser(description="Rebuild and reopen Tabnax whenever native source changes.")
    parser.add_argument("--once", action="store_true", help="build and reopen once, without watching")
    args = parser.parse_args()
    runner = Runner()
    with (runner.work / "watch.lock").open("w") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("A Tabnax development runner is already active. Use r + Enter in its terminal.")
            return 1
        print("Tabnax development runner\nApp: " + str(runner.app), flush=True)
        print("Log: " + str(runner.log), flush=True)
        changes = Changes(snapshot())
        success = runner.reload()
        if args.once:
            return 0 if success else 1
        print("Watching native source. r + Enter: rebuild · Ctrl-C: stop watching, keep the app open.", flush=True)
        stdin_open = True
        while True:
            current = snapshot()
            ready = changes.ready(current, time.monotonic())
            manual = False
            if stdin_open and select.select([sys.stdin], [], [], 0)[0]:
                line = sys.stdin.readline()
                stdin_open = bool(line)
                manual = line.strip().lower() in ("r", "reload")
            if ready or manual:
                changed = sorted(path for path in current.keys() | changes.attempted.keys()
                                 if current.get(path) != changes.attempted.get(path))
                print("Changed: " + ", ".join(changed[:5]) + (" …" if len(changed) > 5 else "")
                      if changed else "Manual reload.", flush=True)
                changes.start()
                runner.reload()
            time.sleep(0.25)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nStopped watching. The last running app stays open.")
