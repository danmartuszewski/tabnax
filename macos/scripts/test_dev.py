import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location("dev", Path(__file__).with_name("dev.py"))
dev = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dev)


class DevelopmentRunnerTests(unittest.TestCase):
    def test_watches_content_additions_and_removals_without_build_or_editor_noise(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "Tabnax/View.swift"
            source.parent.mkdir()
            source.write_text("first")
            original = dev.snapshot(root)
            source.touch()
            self.assertEqual(dev.snapshot(root), original)
            for name in ("Packages/Example/.build/generated.swift", "Tabnax.xcodeproj/xcuserdata/state",
                         "build/DerivedData/generated.swift", "Tabnax/.View.swift.swp"):
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("ignored")
            self.assertEqual(dev.snapshot(root), original)
            source.write_text("other")
            self.assertNotEqual(dev.snapshot(root), original)
            source.unlink()
            self.assertNotIn("Tabnax/View.swift", dev.snapshot(root))

    def test_debounces_saves_and_does_not_miss_edits_during_build(self):
        changes = dev.Changes({"a": "first"})
        self.assertFalse(changes.ready({"a": "second"}, 1))
        self.assertFalse(changes.ready({"a": "third"}, 1.4))
        self.assertTrue(changes.ready({"a": "third"}, 2.1))
        changes.start()
        self.assertFalse(changes.ready({"a": "third"}, 4))
        self.assertFalse(changes.ready({"a": "fourth"}, 4.1))
        self.assertTrue(changes.ready({"a": "fourth"}, 4.8))

    def test_failed_build_never_stops_or_replaces_running_app(self):
        with tempfile.TemporaryDirectory() as temp:
            runner = dev.Runner(Path(temp))
            runner.app.mkdir()
            (runner.app / "version").write_text("working")
            runner.run = Mock(side_effect=subprocess.CalledProcessError(1, "compiler"))
            runner.promote = Mock()
            with patch("builtins.print"):
                self.assertFalse(runner.reload())
            runner.promote.assert_not_called()
            self.assertEqual((runner.app / "version").read_text(), "working")

    def test_successful_reload_installs_whole_bundle_at_stable_path(self):
        with tempfile.TemporaryDirectory() as temp:
            runner = dev.Runner(Path(temp))
            for path, version in ((runner.app, "old"), (runner.staged, "new")):
                path.mkdir()
                (path / "version").write_text(version)
            runner.launch = Mock()
            stopped = subprocess.CompletedProcess([], 0, stdout=str(runner.app)+"\n")
            with runner.log.open("w") as output, patch.object(dev.subprocess, "run", return_value=stopped):
                runner.promote(output)
                runner.launch.assert_called_once_with(runner.app, output)
            self.assertEqual((runner.app / "version").read_text(), "new")
            self.assertEqual((runner.backup / "version").read_text(), "old")
            self.assertFalse(runner.staged.exists())

    def test_failed_launch_restores_previous_bundle(self):
        with tempfile.TemporaryDirectory() as temp:
            runner = dev.Runner(Path(temp))
            for path, version in ((runner.app, "working"), (runner.staged, "broken")):
                path.mkdir()
                (path / "version").write_text(version)
            runner.launch = Mock(side_effect=[subprocess.CalledProcessError(1, "open"), None])
            runner.run = Mock()
            stopped = subprocess.CompletedProcess([], 0, stdout=str(runner.app)+"\n")
            with runner.log.open("w") as output, patch.object(dev.subprocess, "run", return_value=stopped):
                with self.assertRaises(subprocess.CalledProcessError):
                    runner.promote(output)
            self.assertEqual((runner.app / "version").read_text(), "working")
            self.assertEqual(runner.launch.call_count, 2)

    def test_first_failed_dev_launch_reopens_existing_release(self):
        with tempfile.TemporaryDirectory() as temp:
            runner = dev.Runner(Path(temp))
            release = runner.root / "build/DerivedData/Build/Products/Release/Tabnax.app"
            release.mkdir(parents=True)
            runner.staged.mkdir()
            runner.launch = Mock(side_effect=[subprocess.CalledProcessError(1, "open"), None])
            runner.run = Mock()
            stopped = subprocess.CompletedProcess([], 0, stdout=str(release)+"\n")
            with runner.log.open("w") as output, patch.object(dev.subprocess, "run", return_value=stopped):
                with self.assertRaises(subprocess.CalledProcessError):
                    runner.promote(output)
                runner.launch.assert_called_with(release, output)
            self.assertFalse(runner.app.exists())


if __name__ == "__main__":
    unittest.main()
