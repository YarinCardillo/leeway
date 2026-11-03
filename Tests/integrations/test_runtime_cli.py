"""Run installed commands with stub advisors and fake Codex executables."""

import json
import os
import shlex
import subprocess
from pathlib import Path

import pytest

from test_advisor_client import service
from test_install import ROOT

MANAGER = ROOT / "leeway-integrations"
WRAPPER = ROOT / "codex/leeway-codex"


def isolated(tmp_path):
    return {**os.environ, "HOME": str(tmp_path), "CLAUDE_CONFIG_DIR": str(tmp_path / ".claude"),
            "CODEX_HOME": str(tmp_path / ".codex")}


def test_install_run_offline_and_uninstall_in_temporary_home(tmp_path):
    profile = tmp_path / "profile with ' quote"
    profile.mkdir()
    args = [str(MANAGER), "install", "--profile", str(profile), "--provider", "claude",
            "--advisor-url", "http://127.0.0.1:1"]
    result = subprocess.run(args, env=isolated(tmp_path), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    settings = json.loads((profile / "settings.json").read_text())
    command = settings["hooks"]["PreToolUse"][0]["hooks"][0]["command"]
    result = subprocess.run(shlex.split(command), input=json.dumps({"cwd": str(tmp_path),
                            "tool_name": "Agent", "tool_input": {"prompt": "Build"}}),
                            env=isolated(tmp_path), capture_output=True, text=True)
    assert result.returncode == 0
    assert result.stdout == ""
    assert "this call was allowed" in result.stderr
    args[1] = "uninstall"
    result = subprocess.run(args, env=isolated(tmp_path), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert json.loads((profile / "settings.json").read_text()) == {}
    assert not (tmp_path / ".codex").exists()


@pytest.mark.parametrize("payload", ['[1]', '{bad', '{"tool_input":null}',
                                      '{"tool_input":{"command":42},"tool_name":"Bash"}'])
def test_malformed_hook_input_allows_and_warns(tmp_path, payload):
    result = subprocess.run([str(ROOT / "claude-code/leeway-hook"), "run", "PreToolUse"],
                            input=payload, env=isolated(tmp_path), capture_output=True, text=True)
    assert result.returncode == 0
    assert result.stdout == ""
    assert "this call was allowed" in result.stderr


def fake_codex(tmp_path):
    script = tmp_path / "fake-codex"
    script.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\ncat\nexit 7\n')
    script.chmod(0o700)
    return script


def test_codex_wrapper_fail_open_preserves_argv_stdin_and_exit_code(tmp_path):
    script = fake_codex(tmp_path)
    result = subprocess.run([str(WRAPPER), "--advisor-url", "http://127.0.0.1:1", "--",
                             "exec", "-m", "balanced-code", "a; $literal prompt"],
                            input="stdin task", env={**isolated(tmp_path), "LEEWAY_CODEX_COMMAND": str(script)},
                            capture_output=True, text=True)
    assert result.returncode == 7
    assert result.stdout == "exec\n-m\nbalanced-code\na; $literal prompt\nstdin task"
    assert "this call was allowed" in result.stderr


def test_codex_wrapper_deny_does_not_run_process_or_send_prompt(tmp_path, service):
    url, calls = service
    result = subprocess.run([str(WRAPPER), "--advisor-url", url, "--", "exec", "-m", "different", "secret"],
                            env={**isolated(tmp_path), "CODEX_HOME": "/profile",
                                 "LEEWAY_CODEX_COMMAND": str(fake_codex(tmp_path))},
                            capture_output=True, text=True)
    assert result.returncode == 2
    assert result.stdout == ""
    assert "Relaunch" in result.stderr
    assert "secret" not in json.dumps(calls)


def test_installed_codex_wrapper_can_run_without_touching_provider_profile(tmp_path):
    result = subprocess.run([str(MANAGER), "install", "--provider", "codex",
                             "--advisor-url", "http://127.0.0.1:1"], env=isolated(tmp_path),
                            capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    wrapper = tmp_path / ".local/bin/leeway-codex"
    assert wrapper.exists()
    result = subprocess.run([str(wrapper), "exec", "-m", "balanced-code", "task"],
                            env={**isolated(tmp_path), "LEEWAY_CODEX_COMMAND": str(fake_codex(tmp_path))},
                            input="", capture_output=True, text=True)
    assert result.returncode == 7, result.stderr
    assert not (tmp_path / ".codex").exists()
    result = subprocess.run([str(MANAGER), "uninstall", "--provider", "codex"],
                            env=isolated(tmp_path), capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert not wrapper.exists()
