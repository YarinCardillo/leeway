"""Bundled Python entry points must not modify signed application resources."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class IntegrationBundleTests(unittest.TestCase):
    def test_all_entrypoints_leave_their_runtime_tree_unchanged(self):
        for entry in ["leeway-integrations", "claude-code/leeway-hook", "codex/leeway-codex"]:
            with self.subTest(entry=entry), tempfile.TemporaryDirectory() as directory:
                bundle = Path(directory) / "integrations"
                shutil.copytree(ROOT / "integrations", bundle, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
                before = {path.relative_to(bundle) for path in bundle.rglob("*")}
                environment = {key: value for key, value in os.environ.items()
                               if key not in {"PYTHONDONTWRITEBYTECODE", "PYTHONPYCACHEPREFIX"}}
                result = subprocess.run([str(bundle / entry), "--help"], env=environment,
                                        capture_output=True, text=True, timeout=15)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual({path.relative_to(bundle) for path in bundle.rglob("*")}, before)
