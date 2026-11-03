"""Check release tool boundaries on the oldest supported local interpreters."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class ReleaseToolTests(unittest.TestCase):
    def test_stable_omits_channel_while_prerelease_uses_beta_on_bash32(self):
        script = ROOT / "scripts/generate_appcast.sh"
        self.assertTrue(script.exists(), "Testable appcast entry point must exist")
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            generator = root / "generate_appcast"
            generator.write_text(f"#!{sys.executable}\nimport json, os, sys\nopen(os.environ['CAPTURE_ARGS'], 'w').write(json.dumps(sys.argv[1:]))\n")
            generator.chmod(0o755)
            capture = root / "args.json"
            for version in ["0.1.0", "0.1.0-rc.1"]:
                subprocess.run(["/bin/bash", str(script), version, "1", str(root), str(root)],
                               env=dict(os.environ, CAPTURE_ARGS=str(capture)), check=True)
                args = json.loads(capture.read_text())
                self.assertNotIn("", args)
                if "-" in version:
                    self.assertEqual(args[args.index("--channel") + 1], "beta")
                else:
                    self.assertNotIn("--channel", args)

    @unittest.skipUnless(Path("/usr/bin/python3").exists(), "Requires system Python")
    def test_cask_checksum_generation_works_with_system_python(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / "Leeway.zip"
            archive.write_bytes(b"release archive")
            cask = Path(directory) / "leeway.rb"
            result = subprocess.run(["/usr/bin/python3", str(ROOT / "scripts/write_cask.py"),
                                     "0.1.0", str(archive), str(cask)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), cask.read_text())


class ReleaseCaskTests(unittest.TestCase):
    def test_finalization_updates_tracked_and_staged_casks_from_final_zip(self):
        script = (ROOT / "scripts/release.sh").read_text()
        finalization = script[script.index("python3 scripts/write_cask.py "):]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "scripts/write_cask.py").write_bytes((ROOT / "scripts/write_cask.py").read_bytes())
            (root / "Casks").mkdir()
            tracked = root / "Casks/leeway.rb"
            tracked.write_text("previous cask")
            output = root / "releases/0.1.0"
            output.mkdir(parents=True)
            archive = output / "Leeway-0.1.0.zip"
            archive.write_bytes(b"verified final archive")
            (output / "appcast.xml").write_text("verified feed")
            (output / "source-commit.txt").write_text("0" * 40)
            environment = dict(os.environ, VERSION="0.1.0", ZIP=str(archive), OUT=str(output),
                               RELEASES=str(output.parent), REPO="example/leeway", CREATE_DMG="0")
            result = subprocess.run(["/bin/bash", "-c", "set -euo pipefail\nASSETS=()\n" + finalization],
                                    cwd=root, env=environment, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(tracked.read_bytes(), (output / "leeway.rb").read_bytes())
            self.assertIn(hashlib.sha256(archive.read_bytes()).hexdigest(), tracked.read_text())
            self.assertIn('version "0.1.0"', tracked.read_text())
