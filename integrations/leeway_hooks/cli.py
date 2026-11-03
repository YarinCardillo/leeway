"""Standalone entry points, also dispatched by the Leeway CLI."""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from pathlib import Path

from leeway_hooks import hooks, install
from leeway_hooks.client import Advisor, DEFAULT_URL

ROOT = Path(__file__).resolve().parents[1]
ROLES = ("builder", "reviewer", "explorer", "planner", "evaluator")
TASK_CLASSES = ("mechanical", "integration", "design")


def main(argv: list[str] | None = None) -> int:
    """Run a hook or explicitly install/remove integrations; return a CLI exit status."""
    args = _parser().parse_args(argv)
    if args.command == "run":
        return _run(args, dict(os.environ))
    try:
        _manage(args)
        return 0
    except (OSError, ValueError, TypeError) as error:
        print(f"Leeway integration {args.command} failed: {error}", file=sys.stderr)
        return 1


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="leeway integrations")
    commands = parser.add_subparsers(dest="command", required=True, metavar="{install,uninstall}")
    runner = commands.add_parser("run")
    runner.add_argument("event", choices=install.EVENTS)
    runner.add_argument("--config-dir", type=Path)
    runner.add_argument("--role", choices=ROLES)
    runner.add_argument("--task-class", choices=TASK_CLASSES, default="integration")
    runner.add_argument("--managed-by", choices=("leeway-v1",), help=argparse.SUPPRESS)
    for name in ("install", "uninstall"):
        command = commands.add_parser(name, help="Add opt-in agent hooks" if name == "install" else "Remove Leeway hooks")
        command.add_argument("--profile", action="append", type=Path, help="Profile folder to update; repeat for multiple profiles")
        command.add_argument("--provider", choices=("all", "claude", "codex"), default="all", help="Which app to configure (default: all)")
        command.add_argument("--codex-bin", type=Path, help="Destination for the leeway-codex wrapper")
    for command in (runner, *[commands.choices[name] for name in ("install", "uninstall")]):
        command.add_argument("--advisor-url", default=os.environ.get("LEEWAY_ADVISOR_URL", DEFAULT_URL), help="Loopback advisor URL (default: %(default)s)")
    return parser


def _manage(args: argparse.Namespace) -> None:
    uninstall = args.command == "uninstall"
    if args.provider in {"all", "claude"}:
        paths = args.profile or profile_directories(Path.home(), dict(os.environ), Advisor(args.advisor_url))
        for path in install.profiles(paths, ROOT / "claude-code/leeway-hook", args.advisor_url,
                                     uninstall=uninstall):
            print(f"Removed hook from {path}" if uninstall else f"Installed hook in {path}")
    if args.provider in {"all", "codex"}:
        path = args.codex_bin or Path.home() / ".local/bin/leeway-codex"
        install.codex_wrapper(path, ROOT / "codex/leeway-codex", uninstall=uninstall, url=args.advisor_url)
        print(f"Removed wrapper from {path}" if uninstall else f"Installed wrapper in {path}")


def _run(args: argparse.Namespace, env: dict) -> int:
    try:
        if args.config_dir:
            env["CLAUDE_CONFIG_DIR"] = str(args.config_dir)
        payload = json.load(sys.stdin)
        if not isinstance(payload, dict) or not isinstance(payload.get("tool_input", {}), dict):
            raise ValueError("hook input must be an object with an object tool_input")
        output = hooks.evaluate(args.event, payload, Advisor(args.advisor_url), env,
                                role=args.role, task_class=args.task_class)
        if output:
            print(json.dumps(output))
    except Exception as error:
        hooks.warn_unavailable(error)
    return 0


def profile_directories(home: Path, env: dict, advisor) -> list[Path]:
    """Include user-added profiles from cached status, without reading provider credentials."""
    added = []
    try:
        for account in advisor.status()["accounts"]:
            if account["provider"] == "claude":
                added.extend(Path(path) for path in [account["config_dir"], *account.get("aliases", [])])
    except (OSError, ValueError, KeyError, TypeError) as error:
        hooks.warn_unavailable(error)
    return install.discover(home, env, added)
