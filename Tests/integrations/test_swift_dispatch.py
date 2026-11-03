"""Compile the CLI seam independently while the core executable is being built."""

import json
import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="module")
def cli(tmp_path_factory):
    directory = tmp_path_factory.mktemp("swift-cli")
    harness = directory / "main.swift"
    harness.write_text('''import Foundation
        do {
            let status = try IntegrationCommand.run(arguments: Array(CommandLine.arguments.dropFirst()))
            exit(status ?? 64)
        } catch {
            FileHandle.standardError.write(Data("\\(error)\\n".utf8))
            exit(1)
        }
    ''')
    binary = directory / "leeway"
    result = subprocess.run(["swiftc", str(ROOT / "Sources/leeway/IntegrationCommand.swift"),
                             str(harness), "-o", str(binary)], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return binary


def test_swift_cli_install_and_uninstall_in_temp_home(cli, tmp_path):
    profile = tmp_path / ".claude"
    profile.mkdir()
    env = {**os.environ, "HOME": str(tmp_path), "CLAUDE_CONFIG_DIR": str(profile),
           "LEEWAY_INTEGRATIONS_EXECUTABLE": str(ROOT / "integrations/leeway-integrations")}
    args = [str(cli), "integrations", "install", "--profile", str(profile), "--provider", "claude"]
    result = subprocess.run(args, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert "SessionStart" in json.loads((profile / "settings.json").read_text())["hooks"]
    args[2] = "uninstall"
    result = subprocess.run(args, env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert json.loads((profile / "settings.json").read_text()) == {}


def test_swift_dispatch_preserves_nonzero_exit_status_and_literal_arguments(cli, tmp_path):
    script = tmp_path / "runtime with spaces"
    script.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\nexit 3\n')
    script.chmod(0o700)
    result = subprocess.run([str(cli), "integrations", "install", "; echo unsafe"],
                            env={**os.environ, "LEEWAY_INTEGRATIONS_EXECUTABLE": str(script)},
                            capture_output=True, text=True)
    assert result.returncode == 3
    assert result.stdout == "install\n; echo unsafe\n"


def test_swift_dispatch_leaves_other_commands_to_core(cli):
    result = subprocess.run([str(cli), "status"], capture_output=True)
    assert result.returncode == 64


def test_swift_dispatch_missing_runtime_reports_safe_error(cli, tmp_path):
    result = subprocess.run([str(cli), "integrations", "install"],
                            env={**os.environ, "LEEWAY_INTEGRATIONS_EXECUTABLE": str(tmp_path / "missing")},
                            capture_output=True, text=True)
    assert result.returncode == 1
    assert "runtime" in result.stderr
    assert str(tmp_path) not in result.stderr


def test_actual_cli_dispatches_before_loading_invalid_policy(tmp_path):
    build = subprocess.run(["swift", "build", "--product", "leeway"], cwd=ROOT,
                           capture_output=True, text=True, timeout=120)
    assert build.returncode == 0, build.stderr
    policy = tmp_path / "invalid.toml"
    policy.write_text("not valid TOML [")
    runtime = tmp_path / "runtime with spaces"
    runtime.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\nexit 3\n')
    runtime.chmod(0o700)
    result = subprocess.run([str(ROOT / ".build/debug/leeway"), "--policy", str(policy),
                             "integrations", "install", "; echo unsafe"],
                            env={**os.environ, "LEEWAY_INTEGRATIONS_EXECUTABLE": str(runtime)},
                            capture_output=True, text=True, timeout=30)
    assert result.returncode == 3
    assert result.stdout == "install\n; echo unsafe\n"
