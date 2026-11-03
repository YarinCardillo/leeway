"""Recognize direct codex exec invocations without executing shell input."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

from leeway_hooks.shell import segments
VALUE_OPTIONS = {"-m", "--model", "-c", "--config", "-C", "--cd", "--profile", "-p"}


@dataclass(frozen=True)
class Launch:
    """The routing inputs of one direct Codex process."""

    model: str | None
    env: dict
    repo: Path
    is_context_known: bool = True

    @property
    def is_resolved(self) -> bool:
        """Whether account and directory routing use literal, inspectable paths."""
        values = (str(self.repo), self.env.get("CODEX_HOME", ""), self.env.get("HOME", ""))
        return self.is_context_known and all(not value or (Path(value).is_absolute() and "$" not in value and "`" not in value)
                   for value in values)


def launches(command: str, env: dict, cwd: str) -> list[Launch]:
    """Track simple shell directory/environment changes before each direct launch."""
    context, result = _Context(dict(env), Path(cwd)), []
    scopes = []
    for tokens, operator in segments(command):
        if tokens:
            launch = context.command(tokens, operator)
            if launch:
                result.append(launch)
        if operator == "(":
            scopes.append(context)
            context = _Context(dict(context.env), context.repo, context.is_known)
        elif operator == ")":
            context = scopes.pop() if scopes else _Context(dict(env), Path(cwd), False)
        elif operator in {"|", "&", "||"}:
            context.is_known = False
        elif operator in {";", "\n"} and tokens:
            if context.has_conditional_change:
                context.is_known = False
            context.is_guarded = False
        if operator in {"&&", "||"}:
            context.is_guarded = True
    return result


@dataclass
class _Context:
    env: dict
    repo: Path
    is_known: bool = True
    has_conditional_change: bool = False
    is_guarded: bool = False

    def command(self, tokens: list[str], operator: str | None) -> Launch | None:
        if tokens[0] == "cd":
            target = tokens[-1] if len(tokens) > 1 else self.env.get("HOME", str(Path.home()))
            self.repo = _directory(target, self.repo, self.env)
            self.is_known = self.is_known and operator == "&&" and len(tokens) <= 2 and not target.startswith("-")
            self.has_conditional_change = True
        elif tokens[0] in {"export", "unset"}:
            _environment(tokens, self.env)
            self.has_conditional_change |= self.is_guarded
        else:
            args, current = _prefix(tokens, self.env)
            if not args:
                self.env = current
                self.has_conditional_change |= self.is_guarded
            elif Path(args[0]).name == "codex":
                launch = parse_exec(args[1:], current, self.repo)
                if launch:
                    return Launch(launch.model, launch.env, launch.repo, self.is_known)
        return None


def _environment(tokens: list[str], env: dict) -> None:
    for token in tokens[1:]:
        if tokens[0] == "unset":
            env.pop(token, None)
        elif "=" in token:
            key, value = token.split("=", 1)
            env[key] = value


def _prefix(tokens: list[str], env: dict) -> tuple[list[str], dict]:
    local, index = dict(env), 0
    while index < len(tokens):
        token = tokens[index]
        if token == "env":
            index += 1
            while index < len(tokens) and tokens[index].startswith("-"):
                flag = tokens[index]
                if flag in {"-i", "--ignore-environment"}:
                    local.clear()
                elif flag in {"-u", "--unset"} and index + 1 < len(tokens):
                    index += 1
                    local.pop(tokens[index], None)
                index += 1
        elif token == "command":
            index += 1
            while index < len(tokens) and tokens[index] in {"--", "-p"}:
                index += 1
        elif "=" in token and not token.startswith("-"):
            key, value = token.split("=", 1)
            local[key] = value
            index += 1
        else:
            break
    return tokens[index:], local


def parse_exec(args: list[str], env: dict, repo: Path) -> Launch | None:
    """Inspect literal Codex arguments without executing them or reading prompt input."""
    model, is_exec, index = None, False, 0
    while index < len(args):
        token = args[index]
        if token == "--":
            break
        if token in VALUE_OPTIONS:
            if index + 1 >= len(args):
                break
            value = args[index + 1]
            if token in {"-m", "--model"}:
                model = value
            elif token in {"-C", "--cd"}:
                repo = _directory(value, repo, env)
            index += 2
            continue
        if token.startswith("--model="):
            model = token.split("=", 1)[1]
        elif token.startswith("--cd="):
            repo = _directory(token.split("=", 1)[1], repo, env)
        elif token in {"exec", "e"}:
            is_exec = True
        elif not token.startswith("-"):
            break
        index += 1
    return Launch(model, env, repo) if is_exec else None


def _directory(raw: str, base: Path, env: dict) -> Path:
    expanded = raw
    if expanded == "~" or expanded.startswith("~/"):
        expanded = str(Path(env.get("HOME", str(Path.home()))) / expanded[2:])
    path = Path(expanded)
    return (path if path.is_absolute() else base / path).resolve()
