"""Behavioral checks for release inputs and publishable update metadata."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("release_metadata", ROOT / "scripts/release_metadata.py")
metadata = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(metadata)


class ReleaseMetadataTests(unittest.TestCase):
    def test_version_matches_single_source_and_positive_build(self):
        config = "LEEWAY_RELEASE_VERSION = 0.1.0-rc.1\nCURRENT_PROJECT_VERSION = 1\n"
        self.assertEqual(metadata.read_version(config, "0.1.0-rc.1"), ("0.1.0-rc.1", 1))
        for version in ["0.1.0", "../bad", "v0.1.0-rc.1", "0.1.0-rc.01"]:
            with self.subTest(version=version), self.assertRaises(ValueError):
                metadata.read_version(config, version)
        with self.assertRaises(ValueError):
            metadata.read_version(config.replace("VERSION = 1", "VERSION = 0"), "0.1.0-rc.1")

    def test_public_release_inputs_match_the_requested_version(self):
        config = (ROOT / "App/Version.xcconfig").read_text()
        self.assertEqual(metadata.read_version(config, "0.1.0")[0], "0.1.0")
        cask = (ROOT / "Casks/leeway.rb").read_text()
        self.assertIn('version "0.1.0"', cask)
        self.assertTrue(metadata.release_notes((ROOT / "CHANGELOG.md").read_text(), "0.1.0").strip())

    def test_changelog_selects_exact_release_without_unreleased_changes(self):
        changelog = "# Changelog\n\n## Unreleased\n\n- Future.\n\n## 0.1.0-rc.1\n\n- First release.\n\n## 0.0.9\n\n- Old.\n"
        self.assertEqual(metadata.release_notes(changelog, "0.1.0-rc.1"), "- First release.\n")
        with self.assertRaises(ValueError):
            metadata.release_notes(changelog, "0.2.0")

    def test_feed_validates_archive_identity_signature_and_channel(self):
        feed = '''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel>
        <item><sparkle:version>1</sparkle:version><sparkle:shortVersionString>0.1.0-rc.1</sparkle:shortVersionString>
        <sparkle:channel>beta</sparkle:channel><sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
        <enclosure url="https://github.com/YarinCardillo/leeway/releases/download/v0.1.0-rc.1/Leeway-0.1.0-rc.1.zip"
        length="123" sparkle:edSignature="SIGNATURE"/></item></channel></rss>'''
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            path.write_text(feed)
            archive = Path(directory) / "Leeway-0.1.0-rc.1.zip"
            archive.write_bytes(b"x" * 123)
            args = (path, archive, "0.1.0-rc.1", 1, "SIGNATURE")
            metadata.validate_appcast(*args)
            for old, new in [("beta", "stable"), ('length="123"', 'length="124"'), ("/v0.1.0-rc.1/", "/v0.1.0/"), ("SIGNATURE", "WRONG")]:
                with self.subTest(old=old), self.assertRaises(ValueError):
                    path.write_text(feed.replace(old, new))
                    metadata.validate_appcast(*args)


if __name__ == "__main__":
    unittest.main()
