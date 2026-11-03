"""User-facing advice must remain actionable without diagnostic dumps."""

import logging

from leeway_hooks import hooks
from test_enforcement import ENV, StubAdvisor, advice, payload


def test_summary_omits_home_paths_and_labels_the_action():
    response = advice()
    response.update(verdict="deny", config_dir="/home/test/private-profile",
                    retry_at="2026-11-04T05:00:00Z")
    text = hooks.summary(response)
    assert text.startswith("Leeway blocked this call.")
    assert "/home/test" not in text
    assert "config_dir=" not in text
    assert "T05:00:00Z" not in text
    assert "Try again after" in text


def test_unavailable_warning_gives_recovery_without_exception_type(caplog):
    with caplog.at_level(logging.WARNING):
        hooks.warn_unavailable(ConnectionRefusedError("/private/path"))
    assert "Start leeway serve" in caplog.text
    assert "ConnectionRefusedError" not in caplog.text
    assert "/private/path" not in caplog.text


def test_account_switch_includes_shell_quoted_relaunch_command():
    response = advice()
    response.update(verdict="switch", config_dir="/home/test/profile with 'quote")
    output = hooks.evaluate("PreToolUse", payload(), StubAdvisor(response), ENV)
    text = output["hookSpecificOutput"]["permissionDecisionReason"]
    assert 'cd -- /repo && HOME=/home/test CLAUDE_CONFIG_DIR=' in text
    assert "claude --model sonnet" in text
    assert "account/provider" not in text


def test_integration_help_explains_options_and_hides_internal_run():
    import subprocess
    from pathlib import Path
    manager = Path(__file__).resolve().parents[2] / "integrations/leeway-integrations"
    top = subprocess.run([str(manager), "--help"], capture_output=True, text=True, timeout=10)
    assert top.returncode == 0
    assert "{install,uninstall}" in top.stdout
    assert "run" not in top.stdout
    detail = subprocess.run([str(manager), "install", "--help"], capture_output=True, text=True, timeout=10)
    assert "Profile folder" in detail.stdout
    assert "Loopback advisor URL" in detail.stdout


def test_codex_relaunch_preserves_repository_and_redefined_home(tmp_path):
    import json
    import os
    import subprocess
    from leeway_hooks import commands
    repository = tmp_path / "another repository"
    repository.mkdir()
    home = tmp_path / "other home"
    profile = home / "profile with ' quote"
    launch = commands.parse_exec(["exec", "-C", str(repository), "-m", "old"],
                                 {**os.environ, "HOME": str(home)}, tmp_path)
    response = advice()
    response.update(agent="codex", model="new", config_dir=str(profile))
    reason = hooks.codex_denial(launch, response, is_same_account=True)
    command = reason.split("Relaunch with: ", 1)[1]
    binary = tmp_path / "bin"
    binary.mkdir()
    fake = binary / "codex"
    fake.write_text('#!/usr/bin/env python3\nimport json, os, sys\n'
                    'print(json.dumps({"home": os.environ["HOME"], "profile": os.environ["CODEX_HOME"], "args": sys.argv[1:]}))\n')
    fake.chmod(0o700)
    result = subprocess.run(command, shell=True, cwd=tmp_path,
                            env={**os.environ, "PATH": str(binary) + os.pathsep + os.environ["PATH"]},
                            capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, result.stderr
    actual = json.loads(result.stdout)
    assert actual["home"] == str(home)
    assert actual["profile"] == str(profile)
    assert actual["args"][:3] == ["exec", "-C", str(repository)]
