"""Translate quota advice into Claude Code hook decisions."""

from __future__ import annotations

import logging
import shlex
from datetime import datetime
from pathlib import Path

from leeway_hooks import commands

LOG = logging.getLogger(__name__)
ROLES = (("explor", "explorer"), ("plan", "planner"), ("review", "reviewer"), ("evaluat", "evaluator"))


def evaluate(event: str, payload: dict, advisor, env: dict, *, role: str | None = None,
             task_class: str = "integration") -> dict | None:
    """Return a hook decision, allowing work with a warning if the advisor fails."""
    try:
        query = request(payload, "claude", role, task_class)
        if event == "SessionStart":
            return _session(advisor, env, query)
        if event == "UserPromptSubmit":
            advice, _ = advise_for_profile(advisor, query, env, require_account=True)
            if advice["verdict"] == "deny":
                return {"decision": "block", "reason": summary(advice)}
            return _context(event, summary(advice))
        if event == "PreToolUse" and payload.get("tool_name") in {"Agent", "Task"}:
            return _agent(payload, advisor, env, query)
        if event == "PreToolUse" and payload.get("tool_name") == "Bash":
            return _codex(payload, advisor, env, {**query, "agent": "codex"})
    except (OSError, ValueError, KeyError, TypeError) as error:
        warn_unavailable(error)
    return None


def request(payload: dict, agent: str, role: str | None = None, task_class: str = "integration") -> dict:
    """Build only the documented advise request fields, without task text."""
    kind = str(payload.get("tool_input", {}).get("subagent_type", "")).lower()
    role = role or next((value for token, value in ROLES if token in kind), "builder")
    return {"repo": str(payload.get("cwd") or Path.cwd()), "role": role,
            "task_class": task_class, "agent": agent}


def current_config(env: dict, agent: str = "claude") -> Path:
    """Resolve the current provider home, including its default when unset."""
    variable = "CLAUDE_CONFIG_DIR" if agent == "claude" else "CODEX_HOME"
    default = Path(env.get("HOME") or Path.home()) / (".claude" if agent == "claude" else ".codex")
    return Path(env.get(variable) or default).expanduser().resolve()


def summary(advice: dict) -> str:
    """Explain the decision without exposing profile paths or raw protocol fields."""
    action = "blocked this call" if advice["verdict"] in {"deny", "wait"} else "checked this call"
    text = f"Leeway {action}. {advice['reason'].rstrip('.')}."
    if advice.get("model"):
        text += f" Use {advice['model']}" + (f" with {advice['effort']} effort" if advice.get("effort") else "") + "."
    if advice.get("retry_at"):
        retry = datetime.fromisoformat(advice["retry_at"].replace("Z", "+00:00")).astimezone()
        text += f" Try again after {retry.strftime('%a %d %b %Y %H:%M %Z')}."
    return text


def relaunch(advice: dict, env: dict, repo: str | Path | None = None) -> str:
    """Build a literal shell command for the selected account, without prompt text."""
    path = shlex.quote(advice["config_dir"])
    home = shlex.quote(str(env.get("HOME") or Path.home()))
    if advice["agent"] == "claude":
        command = f"HOME={home} CLAUDE_CONFIG_DIR={path} claude"
        if advice.get("model"):
            command += " --model " + shlex.quote(advice["model"])
    else:
        command = f"HOME={home} CODEX_HOME={path} codex exec"
        if repo is not None:
            command += " -C " + shlex.quote(str(repo))
        if advice.get("model"):
            command += " -m " + shlex.quote(advice["model"])
        if advice.get("effort"):
            command += " -c " + shlex.quote('model_reasoning_effort="' + advice["effort"] + '"')
    if advice["agent"] == "claude" and repo is not None:
        command = "cd -- " + shlex.quote(str(repo)) + " && " + command
    return " Relaunch with: " + command


def _agent(payload: dict, advisor, env: dict, query: dict) -> dict:
    advice, is_same_account = advise_for_profile(advisor, query, env)
    reason = summary(advice)
    if advice["verdict"] in {"deny", "wait"}:
        return deny(reason)
    if advice["agent"] != "claude" or not is_same_account:
        return deny(reason + relaunch(advice, env, query["repo"]))
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "additionalContext": reason,
                                   "updatedInput": {**payload["tool_input"], "model": advice["model"]}}}


def deny(reason: str) -> dict:
    """Deny a tool call using Claude Code's event-specific output format."""
    return {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny",
                                   "permissionDecisionReason": reason}}


def _context(event: str, text: str) -> dict:
    return {"hookSpecificOutput": {"hookEventName": event, "additionalContext": text}}


def warn_unavailable(error: Exception) -> None:
    """Warn without exposing service errors, paths, credentials or prompt contents."""
    LOG.warning("Leeway could not check limits, so this call was allowed. Start leeway serve to enforce limits.")


def _session(advisor, env: dict, query: dict) -> dict:
    status = None
    try:
        status = advisor.status()
        query = account_query(status, query, env)
    except (OSError, ValueError, KeyError, TypeError) as error:
        warn_unavailable(error)
    output = _context("SessionStart", summary(advisor.advise(query)))
    if status is not None:
        warning = _account_warning(status, env)
        if warning:
            output["systemMessage"] = warning
            output["hookSpecificOutput"]["additionalContext"] += " " + warning
    return output


def _account_warning(status: dict, env: dict) -> str | None:
    for account in status["accounts"]:
        if not _matches(account, env, "claude") or account.get("status") != "over":
            continue
        forecast = account.get("forecast", {}).get("range_high")
        detail = f" Forecast {forecast:g}%." if isinstance(forecast, (int, float)) else ""
        stale = " (stale snapshot)" if account.get("stale") else ""
        return f"Quota warning: current account {account['label']} is {account['status'].replace('_', ' ')}{stale}.{detail}"
    return None


def _matches(account: dict, env: dict, agent: str) -> bool:
    paths = [account["config_dir"], *account.get("aliases", [])]
    return (account["provider"] == agent
            and current_config(env, agent) in {Path(path).expanduser().resolve() for path in paths})


def account_query(status: dict, query: dict, env: dict, *, require_account: bool = False) -> dict:
    """Bind a discovered profile alias to its stable account id before applying policy."""
    for account in status["accounts"]:
        if _matches(account, env, query["agent"]):
            return {**query, "account": account["id"]}
    if require_account:
        raise ValueError("current account is not in advisor status")
    return query


def advise_for_profile(advisor, query: dict, env: dict, *, require_account: bool = False) -> tuple[dict, bool]:
    """Return advice and whether its destination belongs to the current account or alias."""
    status = advisor.status()
    query = account_query(status, query, env, require_account=require_account)
    advice = advisor.advise(query)
    return advice, _same_account(status, advice, env)


def _same_account(status: dict, advice: dict, env: dict) -> bool:
    if advice["agent"] not in {"claude", "codex"}:
        return False
    destination = Path(advice["config_dir"]).expanduser().resolve()
    for account in status["accounts"]:
        if account["id"] == advice["account"] and _matches(account, env, advice["agent"]):
            paths = [account["config_dir"], *account.get("aliases", [])]
            return destination in {Path(path).expanduser().resolve() for path in paths}
    return False


def _codex(payload: dict, advisor, env: dict, query: dict) -> dict | None:
    command = payload.get("tool_input", {}).get("command", "")
    for launch in commands.launches(command, env, query["repo"]):
        if not launch.is_resolved:
            return deny("Relaunch codex exec with absolute literal account and repository paths in a separate command.")
        advice, is_same_account = advise_for_profile(advisor, {**query, "repo": str(launch.repo)}, launch.env)
        reason = codex_denial(launch, advice, is_same_account=is_same_account)
        if reason:
            return deny(reason)
    return None


def codex_denial(launch: commands.Launch, advice: dict, *, is_same_account: bool | None = None) -> str | None:
    """Require an explicit relaunch when a Codex route cannot safely run unchanged."""
    if advice["verdict"] in {"deny", "wait"}:
        return summary(advice)
    if not launch.is_resolved:
        return summary(advice) + relaunch(advice, launch.env, launch.repo) + " from the repository folder, using literal paths."
    if is_same_account is None:
        is_same_account = Path(advice["config_dir"]).expanduser().resolve() == current_config(launch.env, "codex")
    if (advice["agent"] != "codex" or (advice["model"] and launch.model != advice["model"])
            or not is_same_account):
        return summary(advice) + relaunch(advice, launch.env, launch.repo)
    return None
