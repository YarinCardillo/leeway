"""Explicit and reversible installation, always inside temporary homes."""

import json
import shlex
from pathlib import Path

import pytest

from leeway_hooks import install

ROOT = Path(__file__).resolve().parents[2] / "integrations"
RUNNER = ROOT / "claude-code/leeway-hook"


def test_discovery_uses_temp_home_environment_added_and_managed_profiles(tmp_path):
    paths = [tmp_path / ".claude", tmp_path / "custom", tmp_path / "added",
             tmp_path / "Library/Application Support/orca/claude-profiles/one/home"]
    for path in paths:
        path.mkdir(parents=True)
    alias = tmp_path / "Library/Application Support/orca/claude-profiles/two/home"
    alias.parent.mkdir(parents=True)
    alias.symlink_to(paths[0], target_is_directory=True)
    env = {"HOME": str(tmp_path), "CLAUDE_CONFIG_DIR": str(paths[1])}
    assert set(install.discover(tmp_path, env, [paths[2]])) == set(paths)
    assert not (tmp_path / ".codex").exists()


def test_install_and_uninstall_preserve_unrelated_hooks_and_settings(tmp_path):
    settings = tmp_path / "settings.json"
    original = {"model": "existing", "hooks": {"PreToolUse": [
        {"matcher": "Bash", "hooks": [{"type": "command", "command": "existing"}]}]}}
    settings.write_text(json.dumps(original))
    settings.chmod(0o640)
    install.profiles([tmp_path], RUNNER)
    first = settings.read_bytes()
    install.profiles([tmp_path], RUNNER)
    assert settings.read_bytes() == first
    value = json.loads(first)
    for event in install.EVENTS:
        tokens = shlex.split(value["hooks"][event][-1]["hooks"][0]["command"])
        assert tokens[:3] == [str(RUNNER), "run", event]
        assert tokens[tokens.index("--config-dir") + 1] == str(tmp_path)
    assert settings.stat().st_mode & 0o777 == 0o640
    install.profiles([tmp_path], RUNNER, uninstall=True)
    assert json.loads(settings.read_text()) == original
    unchanged = settings.read_bytes()
    install.profiles([tmp_path], RUNNER, uninstall=True)
    assert settings.read_bytes() == unchanged


def test_reconfiguration_replaces_owned_commands_but_keeps_shared_groups(tmp_path):
    install.profiles([tmp_path], RUNNER)
    settings = tmp_path / "settings.json"
    value = json.loads(settings.read_text())
    value["hooks"]["SessionStart"][0]["hooks"].append({"type": "command", "command": "other"})
    settings.write_text(json.dumps(value))
    install.profiles([tmp_path], RUNNER, "http://127.0.0.1:8800")
    value = json.loads(settings.read_text())
    groups = value["hooks"]["SessionStart"]
    assert len(groups) == 2
    assert groups[0]["hooks"] == [{"type": "command", "command": "other"}]
    assert "8800" in groups[1]["hooks"][0]["command"]
    install.profiles([tmp_path], RUNNER, uninstall=True)
    assert json.loads(settings.read_text())["hooks"]["SessionStart"] == groups[:1]


@pytest.mark.parametrize("value", [[], {"hooks": []}, {"hooks": {"PreToolUse": {}}},
                                  {"hooks": {"SessionStart": [None]}},
                                  {"hooks": {"SessionStart": [{"hooks": "bad"}]}}])
def test_malformed_settings_are_never_overwritten(tmp_path, value):
    settings = tmp_path / "settings.json"
    original = json.dumps(value)
    settings.write_text(original)
    with pytest.raises(ValueError):
        install.profiles([tmp_path], RUNNER)
    assert settings.read_text() == original


def test_refuses_symlinked_settings_and_missing_profiles(tmp_path):
    target = tmp_path / "outside.json"
    target.write_text('{}')
    profile = tmp_path / "profile"
    profile.mkdir()
    (profile / "settings.json").symlink_to(target)
    with pytest.raises(ValueError, match="symlink"):
        install.profiles([profile], RUNNER)
    assert target.read_text() == '{}'
    with pytest.raises(ValueError, match="does not exist"):
        install.profiles([tmp_path / "missing"], RUNNER)


def test_rerun_repairs_partial_multi_profile_install(tmp_path):
    first, second = tmp_path / "first", tmp_path / "second"
    first.mkdir()
    second.mkdir()
    (second / "settings.json").write_text('{bad')
    with pytest.raises(ValueError):
        install.profiles([first, second], RUNNER)
    assert (first / "settings.json").exists()
    (second / "settings.json").write_text('{}')
    install.profiles([first, second], RUNNER)
    assert len(json.loads((first / "settings.json").read_text())["hooks"]["SessionStart"]) == 1
    assert (second / "settings.json").exists()


def test_uninstall_with_no_settings_does_not_create_files(tmp_path):
    install.profiles([tmp_path], RUNNER, uninstall=True)
    assert list(tmp_path.iterdir()) == []


def test_atomic_write_failure_keeps_previous_settings(tmp_path, monkeypatch):
    settings = tmp_path / "settings.json"
    settings.write_text('{}')
    def fail(*args):
        raise OSError("disk unavailable")
    monkeypatch.setattr(install.os, "replace", fail)
    with pytest.raises(OSError):
        install.profiles([tmp_path], RUNNER)
    assert settings.read_text() == '{}'
    assert list(tmp_path.iterdir()) == [settings]


def test_wrapper_install_is_idempotent_and_removes_only_owned_file(tmp_path):
    path = tmp_path / "bin/leeway-codex"
    install.codex_wrapper(path, ROOT / "codex/leeway-codex")
    first = path.read_bytes()
    install.codex_wrapper(path, ROOT / "codex/leeway-codex")
    assert path.read_bytes() == first
    assert path.stat().st_mode & 0o777 == 0o700
    install.codex_wrapper(path, ROOT / "codex/leeway-codex", uninstall=True)
    assert not path.exists()
    path.write_text("user script")
    with pytest.raises(ValueError):
        install.codex_wrapper(path, ROOT / "codex/leeway-codex")
    install.codex_wrapper(path, ROOT / "codex/leeway-codex", uninstall=True)
    assert path.read_text() == "user script"


def test_uninstall_does_not_reformat_unowned_settings(tmp_path):
    settings = tmp_path / "settings.json"
    original = '{ "hooks": {"SessionStart": [{"hooks": []}]}, "custom": true }'
    settings.write_text(original)
    install.profiles([tmp_path], RUNNER, uninstall=True)
    assert settings.read_text() == original


def test_cli_discovery_includes_advisor_accounts_and_aliases_without_credentials(tmp_path):
    from leeway_hooks import cli
    primary, alias = tmp_path / "added", tmp_path / "alias"
    primary.mkdir()
    alias.mkdir()
    (primary / "auth.json").write_bytes(b'not valid credentials')
    class Snapshot:
        def status(self):
            return {"accounts": [{"provider": "claude", "config_dir": str(primary),
                                   "aliases": [str(alias)]}]}
    assert set(cli.profile_directories(tmp_path, {}, Snapshot())) == {primary, alias}


def test_cli_discovery_falls_back_to_local_profiles_when_advisor_is_down(tmp_path, caplog):
    from leeway_hooks import cli
    (tmp_path / ".claude").mkdir()
    class Offline:
        def status(self):
            raise OSError("offline")
    assert cli.profile_directories(tmp_path, {}, Offline()) == [tmp_path / ".claude"]
    assert "this call was allowed" in caplog.text
