#!/usr/bin/env python3
"""Scan only publication candidates, then all Git history. Never print secrets."""

import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

from check_repository import ROOT, check, public_files


def main():
    if check():
        return 1
    executable = os.environ.get("GITLEAKS_BIN", "gitleaks")
    if not shutil.which(executable):
        print("Gitleaks is required. See scripts/README.md for the verified installer.", file=sys.stderr)
        return 1
    common = ["--config", str(ROOT / ".gitleaks.toml"), "--redact", "--no-banner"]
    with tempfile.TemporaryDirectory(prefix="tabnax-public-scan-") as directory:
        for name in public_files():
            destination = Path(directory) / name
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, destination, follow_symlinks=False)
        subprocess.run([executable, "dir", directory, *common], check=True)
    has_history = subprocess.run(["git", "rev-parse", "--verify", "HEAD"], cwd=ROOT,
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
    if has_history:
        subprocess.run([executable, "git", str(ROOT), "--log-opts=--all", *common], check=True)
    else:
        print("No commits exist; candidate files scanned, no Git history to scan.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
