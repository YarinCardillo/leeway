"""Exercise the shell boundary without signing or contacting external services."""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/release.sh"
FIRST_BUILD_CONFIG = re.sub(r"(?m)^CURRENT_PROJECT_VERSION = \d+$", "CURRENT_PROJECT_VERSION = 1",
                            (ROOT / "App/Version.xcconfig").read_text())
CURRENT = re.search(r"^LEEWAY_RELEASE_VERSION = (\S+)$", (ROOT / "App/Version.xcconfig").read_text(), re.M).group(1)


class ReleaseEntrypointTests(unittest.TestCase):
    def test_bad_arguments_stop_before_build_or_publication(self):
        self.assertTrue(SCRIPT.is_file(), "Release entry point must exist")
        for arguments in [[], ["../invalid"], ["0.2.0"], ["0.1.0", "extra"]]:
            with self.subTest(arguments=arguments):
                result = subprocess.run(["/bin/bash", str(SCRIPT), *arguments],
                                        capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("gh release create", result.stdout)
                self.assertNotIn("Command line invocation", result.stdout)
                self.assertTrue(result.stderr.strip())

    def test_failed_build_never_produces_publish_instructions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "scripts", root / "scripts")
            (root / "App").mkdir()
            (root / "App/Version.xcconfig").write_text(FIRST_BUILD_CONFIG)
            shutil.copy(ROOT / "CHANGELOG.md", root / "CHANGELOG.md")
            tools = root / "tools"
            tools.mkdir()
            for name, body in {
                "git": 'if [ "$1" != status ]; then printf "%040d\\n" 0; fi\n',
                "xcodebuild": "printf 'intentional build failure\\n' >&2\nexit 73\n",
            }.items():
                command = tools / name
                command.write_text("#!/bin/sh\n" + body)
                command.chmod(0o755)
            environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"])
            result = subprocess.run(["/bin/bash", str(root / "scripts/release.sh"), CURRENT],
                                    env=environment, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 73, result.stdout + result.stderr)
            self.assertNotIn("gh release create", result.stdout)
            output = root / ".build/releases" / CURRENT
            self.assertFalse((output / "publish-draft.sh").exists())
            self.assertIn("intentional build failure", (output / "logs/resolve.log").read_text())

    def release_fixture(self, root):
        shutil.copytree(ROOT / "scripts", root / "scripts")
        (root / "App").mkdir()
        (root / "App/Version.xcconfig").write_text(FIRST_BUILD_CONFIG)
        shutil.copy(ROOT / "CHANGELOG.md", root / "CHANGELOG.md")
        (root / ".gitignore").write_text(".build/\n")
        (root / "scripts/sign_bundle.py").write_text(
            "from pathlib import Path\nPath('.build/signed').touch()\nraise SystemExit(74)\n")
        subprocess.run(["git", "init", "-q", str(root)], check=True)
        subprocess.run(["git", "add", "."], cwd=root, check=True)
        subprocess.run(["git", "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
                        "-c", "commit.gpgsign=false", "commit", "-qm", "fixture"], cwd=root, check=True)
        tools = root / ".build/tools"
        tools.mkdir(parents=True)
        return tools

    def fake_tool(self, tools, name, body):
        path = tools / name
        path.write_text("#!/bin/bash\nset -eu\n" + body)
        path.chmod(0o755)

    def run_fixture(self, root, tools, **extra):
        environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"], **extra)
        return subprocess.run(["/bin/bash", str(root / "scripts/release.sh"), CURRENT],
                              env=environment, capture_output=True, text=True, timeout=15)

    def test_dirty_or_untracked_tree_refused_before_outputs_or_build(self):
        for untracked in [False, True]:
            with self.subTest(untracked=untracked), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                tools = self.release_fixture(root)
                self.fake_tool(tools, "xcodebuild", "touch .build/built\nexit 73\n")
                (root / ("untracked.txt" if untracked else "CHANGELOG.md")).write_text("changed\n")
                result = self.run_fixture(root, tools)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("clean worktree", result.stderr)
                self.assertFalse((root / ".build/built").exists())
                self.assertFalse((root / ".build/releases").exists())

    def test_tree_changed_during_build_refused_before_signing(self):
        for untracked in [False, True]:
            with self.subTest(untracked=untracked), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                tools = self.release_fixture(root)
                target = "untracked.txt" if untracked else "CHANGELOG.md"
                self.fake_tool(tools, "xcodebuild", """if [[ $1 != -resolvePackageDependencies ]]; then
    mkdir -p .build/xcode/Build/Products/Release/Leeway.app
    printf changed > "$DIRTY_TARGET"
fi
""")
                keys = root / ".build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin"
                keys.mkdir(parents=True)
                self.fake_tool(keys, "generate_keys", "sed -n 's/^LEEWAY_UPDATE_PUBLIC_KEY = //p' App/Version.xcconfig\n")
                for name in ["swift", "lipo", "rsync"]:
                    self.fake_tool(tools, name, "exit 0\n")
                self.fake_tool(tools, "ditto", 'mkdir -p "$2"\n')
                result = self.run_fixture(root, tools, DIRTY_TARGET=target)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("clean worktree", result.stdout + result.stderr)
                self.assertFalse((root / ".build/signed").exists())
                self.assertTrue((root / ".build/releases" / CURRENT / "logs/app-build.log").exists())
