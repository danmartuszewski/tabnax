from datetime import datetime, timezone
from pathlib import Path
import sys
import unittest
import xml.etree.ElementTree as ET

sys.path.insert(0, str(Path(__file__).resolve().parent))
import release_metadata as metadata

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


class BuildNumberTests(unittest.TestCase):
    def test_build_numbers_increase_with_semver(self):
        versions = ["0.1.0", "0.1.1", "0.2.0", "0.10.0", "1.0.0", "1.0.10", "2.0.0"]
        numbers = [int(metadata.build_number(v)) for v in versions]
        self.assertEqual(numbers, sorted(numbers))
        self.assertEqual(len(set(numbers)), len(numbers))
        self.assertEqual(metadata.build_number("0.1.0"), "1000")

    def test_rejects_non_release_versions(self):
        for version in ["1.0", "v1.0.0", "1.0.0-beta.1", "01.0.0", "1.1000.0"]:
            with self.assertRaises(ValueError, msg=version):
                metadata.build_number(version)


class AppcastTests(unittest.TestCase):
    def test_appcast_item_matches_release(self):
        feed = metadata.appcast("1.2.3", 4096, "c2lnbmF0dXJl==", "## Fixes\n\n* Faster ]]> search",
                                published=datetime(2026, 9, 24, tzinfo=timezone.utc))
        item = ET.fromstring(feed).find("channel/item")
        self.assertEqual(item.findtext(f"{SPARKLE}version"), "1002003")
        self.assertEqual(item.findtext(f"{SPARKLE}shortVersionString"), "1.2.3")
        self.assertEqual(item.findtext(f"{SPARKLE}minimumSystemVersion"), "15.0")
        self.assertEqual(item.findtext(f"{SPARKLE}hardwareRequirements"), "arm64")
        self.assertIn("]]> search", item.findtext("description"))
        self.assertEqual(item.find("description").get(f"{SPARKLE}format"), "markdown")
        enclosure = item.find("enclosure")
        self.assertEqual(enclosure.get("url"),
                         "https://github.com/danmartuszewski/tabnax/releases/download/v1.2.3/Tabnax-1.2.3.dmg")
        self.assertEqual(enclosure.get("length"), "4096")
        self.assertEqual(enclosure.get(f"{SPARKLE}edSignature"), "c2lnbmF0dXJl==")

    def test_notes_are_optional(self):
        item = ET.fromstring(metadata.appcast("0.1.0", 1, "sig")).find("channel/item")
        self.assertIsNone(item.find("description"))


class CaskTests(unittest.TestCase):
    def test_cask_pins_version_and_checksum(self):
        cask = metadata.cask("0.1.0", "a" * 64)
        self.assertIn('version "0.1.0"', cask)
        self.assertIn(f'sha256 "{"a" * 64}"', cask)
        self.assertIn('url "https://github.com/danmartuszewski/tabnax/releases/download/v#{version}/Tabnax-#{version}.dmg"', cask)
        self.assertIn("auto_updates true", cask)

    def test_cask_rejects_bad_checksum(self):
        with self.assertRaises(ValueError):
            metadata.cask("0.1.0", "ABC")


if __name__ == "__main__":
    unittest.main()
