"""Opt-in Codex wrapper: inspect argv, then exec without reading prompt or stdin."""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from leeway_hooks import commands, hooks
from leeway_hooks.client import Advisor, DEFAULT_URL
from leeway_hooks.cli import ROLES, TASK_CLASSES


def main(argv: list[str] | None = None) -> int:
    """Check a direct Codex exec request and replace this process when allowed."""
    parser = argparse.ArgumentParser(prog="leeway-codex")
    parser.add_argument("--advisor-url", default=os.environ.get("LEEWAY_ADVISOR_URL", DEFAULT_URL))
    parser.add_argument("--role", choices=ROLES, default="builder")
    parser.add_argument("--task-class", choices=TASK_CLASSES, default="integration")
    parser.add_argument("args", nargs=argparse.REMAINDER)
    options = parser.parse_args(argv)
    args = options.args[1:] if options.args[:1] == ["--"] else options.args
    reason = _check(args, options)
    if reason:
        print(reason, file=sys.stderr)
        return 2
    try:
        command = os.environ.get("LEEWAY_CODEX_COMMAND", "codex")
        os.execvpe(command, [command, *args], dict(os.environ))
    except OSError as error:
        print("Leeway could not start Codex. Check that Codex is installed and available in PATH.", file=sys.stderr)
        return 127


def _check(args: list[str], options: argparse.Namespace) -> str | None:
    try:
        launch = commands.parse_exec(args, dict(os.environ), Path.cwd())
        if launch is None:
            return None
        query = {"repo": str(launch.repo), "role": options.role,
                 "task_class": options.task_class, "agent": "codex"}
        advice, is_same_account = hooks.advise_for_profile(Advisor(options.advisor_url), query, launch.env)
        return hooks.codex_denial(launch, advice, is_same_account=is_same_account)
    except Exception as error:
        hooks.warn_unavailable(error)
    return None
