"""Regression checks for accidental publication, including force-added artifacts."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_repository import forbidden_path, link_error, public_files


class PublicationTests(unittest.TestCase):
    def test_private_and_build_paths_are_rejected(self):
        for name in (".env", ".env.production", "macos/Signing.local.xcconfig",
                     "keys/developer.p12", "macos/build/app.txt", "output/capture.png",
                     "macos/verification/run/results.json", ".claude/settings.json"):
            with self.subTest(name=name):
                self.assertTrue(forbidden_path(name))

    def test_reviewed_source_is_allowed(self):
        for name in (".env.example", "macos/Tabnax/AppDelegate.swift", "website/assets/native/mode-shore.png",
                     "macos/verification/run/README.md", ".github/workflows/ci.yml"):
            self.assertFalse(forbidden_path(name), name)

    def test_tracked_ignored_files_cannot_hide_from_scan(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            (root / ".gitignore").write_text(".env\n")
            (root / ".env").write_text("not-a-real-credential\n")
            self.assertNotIn(".env", public_files(root))
            subprocess.run(["git", "add", "-f", ".env"], cwd=root, check=True)
            self.assertIn(".env", public_files(root))
            self.assertTrue(forbidden_path(".env"))

    def test_website_cannot_link_outside_deployment_root(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            candidates = {"website/index.html", "website/guide.html", "README.md"}
            self.assertIsNone(link_error("website/index.html", "guide.html", candidates, root, True))
            self.assertIsNotNone(link_error("website/index.html", "../README.md", candidates, root, True))
            self.assertIsNotNone(link_error("website/index.html", "missing.png", candidates, root, True))


if __name__ == "__main__":
    unittest.main()
