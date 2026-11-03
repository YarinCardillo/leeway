"""Verify universal architecture checks against actual toolchain outputs."""
import importlib.util
from pathlib import Path
import shutil
import plistlib
import subprocess
import sys
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("sign_bundle", Path(__file__).resolve().parents[2] / "scripts/sign_bundle.py")
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)


@unittest.skipUnless(sys.platform == "darwin" and shutil.which("clang"), "Requires Apple toolchain")
class UniversalBinaryTests(unittest.TestCase):
    def test_universal_binary_accepts_both_slices_and_rejects_thin_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / "main.c"
            source.write_text("int main(void) { return 0; }\n")
            images = [root / arch for arch in ("arm64", "x86_64")]
            for image in images:
                subprocess.run(["clang", "-target", image.name + "-apple-macos14", str(source), "-o", str(image)], check=True, capture_output=True)
            universal = root / "universal"
            subprocess.run(["lipo", "-create", *map(str, images), "-output", str(universal)], check=True)
            signing.verify_universal(universal)
            with self.assertRaises(subprocess.CalledProcessError):
                signing.verify_universal(images[0])


class SigningOrderTests(unittest.TestCase):
    def test_main_executable_is_signed_with_bundle_after_cli_sibling(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Leeway.app"
            main = app / "Contents/MacOS/Leeway"
            cli = app / "Contents/Helpers/leeway"
            for image in [main, cli]:
                image.parent.mkdir(parents=True)
                image.write_bytes(bytes.fromhex("cafebabe"))
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable": "Leeway"}))
            targets = signing.signing_targets(app)
            self.assertIn(cli, targets)
            self.assertNotIn(main, targets)
            self.assertEqual(targets[-1], app)
