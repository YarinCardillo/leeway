"""Explicit, atomic per-file installation and removal of owned integrations."""

from __future__ import annotations

import json
import os
import shlex
import tempfile
from pathlib import Path

from leeway_hooks.client import Advisor, DEFAULT_URL

EVENTS = ("PreToolUse", "SessionStart", "UserPromptSubmit")
MANAGED_ARGUMENT = "--managed-by=leeway-v1"
WRAPPER_MARKER = "# Managed by leeway integrations v1\n"
ORCA_PROFILES = "Library/Application Support/orca/claude-profiles/*/home"


def discover(home: Path, env: dict, added: list[Path] = ()) -> list[Path]:
    """Find existing Claude directories without opening credentials or creating profiles."""
    found = [home / ".claude", *added, *sorted(home.glob(ORCA_PROFILES))]
    if env.get("CLAUDE_CONFIG_DIR"):
        raw = env["CLAUDE_CONFIG_DIR"]
        found.append(home / raw[2:] if raw.startswith("~/") else Path(raw))
    return list(dict.fromkeys(path.resolve() for path in found if path.is_dir()))


def profiles(directories: list[Path], runner: Path, url: str = DEFAULT_URL,
             *, uninstall: bool = False) -> list[Path]:
    """Merge or remove owned Claude hooks; retries safely repair a partial installation."""
    if not uninstall:
        Advisor(url)
    written = []
    for directory in dict.fromkeys(path.expanduser().resolve() for path in directories):
        if not directory.is_dir():
            raise ValueError(f"profile directory does not exist: {directory}")
        path = directory / "settings.json"
        if path.is_symlink():
            raise ValueError("profile settings must not be a symlink")
        if uninstall and not path.exists():
            continue
        original = path.read_bytes() if path.exists() else None
        value = json.loads(original) if original is not None else {}
        _validate(value)
        before = json.dumps(value, sort_keys=True)
        _merge(value, directory, runner, url, uninstall)
        if uninstall and before == json.dumps(value, sort_keys=True):
            continue
        encoded = (json.dumps(value, indent=2) + "\n").encode()
        if original != encoded:
            _write(path, encoded)
        written.append(path)
    return written


def codex_wrapper(path: Path, runner: Path, *, uninstall: bool = False,
                  url: str = DEFAULT_URL) -> None:
    """Install an explicit wrapper without changing Codex profiles or shell startup files."""
    if path.is_symlink():
        raise ValueError("Codex wrapper must not be a symlink")
    if path.exists():
        owned = WRAPPER_MARKER in path.read_text().splitlines(keepends=True)[:2]
        if uninstall:
            if owned:
                path.unlink()
            return
        if not owned:
            raise ValueError("refusing to replace an unowned Codex wrapper")
    if uninstall:
        return
    Advisor(url)
    command = shlex.join([str(runner.resolve()), "--advisor-url", url, "--"])
    content = f'#!/bin/sh\n{WRAPPER_MARKER}exec {command} "$@"\n'
    path.parent.mkdir(parents=True, exist_ok=True)
    _write(path, content.encode(), default_mode=0o700)


def _validate(value: dict) -> None:
    if not isinstance(value, dict) or not isinstance(value.get("hooks", {}), dict):
        raise ValueError("profile settings and hooks must be objects")
    for event in EVENTS:
        groups = value.get("hooks", {}).get(event, [])
        if not isinstance(groups, list):
            raise ValueError(f"{event} hooks must be a list")
        for group in groups:
            if not isinstance(group, dict) or not isinstance(group.get("hooks"), list):
                raise ValueError(f"{event} hook groups must contain a hooks list")
            if not all(isinstance(hook, dict) for hook in group["hooks"]):
                raise ValueError(f"{event} hook handlers must be objects")


def _merge(value: dict, directory: Path, runner: Path, url: str, uninstall: bool) -> None:
    hooks = value.setdefault("hooks", {}) if not uninstall else value.get("hooks", {})
    for event in EVENTS:
        groups = []
        for group in hooks.get(event, []):
            remaining = [hook for hook in group["hooks"] if not _owned(hook)]
            if remaining or not group["hooks"]:
                groups.append({**group, "hooks": remaining})
        if not uninstall:
            command = shlex.join([str(runner.resolve()), "run", event, MANAGED_ARGUMENT,
                                  "--config-dir", str(directory), "--advisor-url", url])
            group = {"hooks": [{"type": "command", "command": command, "timeout": 5}]}
            if event == "PreToolUse":
                group["matcher"] = "^(Agent|Task|Bash)$"
            groups.append(group)
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)
    if not hooks:
        value.pop("hooks", None)


def _owned(hook: dict) -> bool:
    if hook.get("type") != "command" or not isinstance(hook.get("command"), str):
        return False
    try:
        args = shlex.split(hook["command"])
    except ValueError:
        return False
    return (len(args) >= 4 and Path(args[0]).name == "leeway-hook"
            and args[1] == "run" and args[2] in EVENTS and args[3] == MANAGED_ARGUMENT)


def _write(path: Path, data: bytes, *, default_mode: int = 0o600) -> None:
    descriptor, temporary = tempfile.mkstemp(prefix=".leeway-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            mode = path.stat().st_mode & 0o777 if path.exists() else default_mode
            os.fchmod(output.fileno(), mode)
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        Path(temporary).unlink(missing_ok=True)
