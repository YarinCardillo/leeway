"""Check actual command boundaries without evaluating shell input."""

import pytest

from leeway_hooks import hooks
from test_enforcement import ENV, StubAdvisor, advice


def codex_advisor(**changes):
    response = advice()
    response.update(agent="codex", account="code", model="balanced-code", config_dir="/home/test/.codex", **changes)
    return StubAdvisor(response)


def bash(command):
    return {"cwd": "/repo", "tool_name": "Bash", "tool_input": {"command": command}}


@pytest.mark.parametrize("command", [
    'codex exec -m balanced-code "work"',
    'cd /repo && /usr/local/bin/codex exec --model=balanced-code "work"',
    'env CODEX_HOME=/home/test/.codex codex exec -m balanced-code "work"',
    'CODEX_HOME=/home/test/.codex codex -m balanced-code exec "work"',
])
def test_codex_advised_model_can_proceed(command):
    advisor = codex_advisor()
    assert hooks.evaluate("PreToolUse", bash(command), advisor, ENV) is None
    assert advisor.requests[0]["agent"] == "codex"


@pytest.mark.parametrize("command", [
    'codex exec -m expensive "work"',
    'codex exec "work"',
    'codex exec -m balanced-code "one"; codex exec -m expensive "two"',
    'CODEX_HOME=/other codex exec -m balanced-code "work"',
])
def test_codex_wrong_model_or_account_is_denied(command):
    result = hooks.evaluate("PreToolUse", bash(command), codex_advisor(), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert "balanced-code" in result["hookSpecificOutput"]["permissionDecisionReason"]


@pytest.mark.parametrize("verdict", ["deny", "wait"])
def test_codex_denied_by_service_even_with_matching_model(verdict):
    result = hooks.evaluate("PreToolUse", bash('codex exec -m balanced-code "work"'), codex_advisor(verdict=verdict), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


@pytest.mark.parametrize("command", ['echo "codex exec -m expensive"', 'git status', 'echo codex exec -m expensive', 'codex --version'])
def test_non_launch_commands_are_untouched(command):
    assert hooks.evaluate("PreToolUse", bash(command), object(), ENV) is None


@pytest.mark.parametrize("command", [
    'codex exec -C /other -m balanced-code task',
    'codex --cd=/other exec -m balanced-code task',
    'cd /other && codex exec -m balanced-code task',
])
def test_codex_advice_uses_effective_repository(command):
    advisor = codex_advisor()
    hooks.evaluate("PreToolUse", bash(command), advisor, ENV)
    assert advisor.requests[0]["repo"] == "/other"


@pytest.mark.parametrize("command", [
    'export CODEX_HOME=/other; codex exec -m balanced-code task',
    'CODEX_HOME=/other; codex exec -m balanced-code task',
    'env -u CODEX_HOME CODEX_HOME=/other codex exec -m balanced-code task',
])
def test_codex_account_changes_are_enforced(command):
    result = hooks.evaluate("PreToolUse", bash(command), codex_advisor(), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


@pytest.mark.parametrize("separator", [";\n", "&&\n", "\n", ";\n\n"])
def test_codex_launch_after_multiline_separator_is_checked(separator):
    result = hooks.evaluate("PreToolUse", bash('echo prep' + separator + 'codex exec -m expensive task'), codex_advisor(), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_unset_codex_home_restores_default_account():
    env = {**ENV, "CODEX_HOME": "/other"}
    result = hooks.evaluate("PreToolUse", bash('unset CODEX_HOME; codex exec -m balanced-code task'), codex_advisor(), env)
    assert result is None


def test_command_local_account_does_not_leak_to_next_launch():
    command = 'CODEX_HOME=/home/test/.codex codex exec -m balanced-code one; codex exec -m balanced-code two'
    result = hooks.evaluate("PreToolUse", bash(command), codex_advisor(), {**ENV, "CODEX_HOME": "/other"})
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_quoted_literal_environment_variable_cannot_authorize_another_account():
    command = "CODEX_HOME='$HOME/.codex' codex exec -m balanced-code task"
    result = hooks.evaluate("PreToolUse", bash(command), codex_advisor(), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_dynamic_directory_requires_an_explicit_relaunch():
    command = 'cd "$DESTINATION" && codex exec -m balanced-code task'
    result = hooks.evaluate("PreToolUse", bash(command), codex_advisor(), {**ENV, "DESTINATION": "/other"})
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_relative_account_path_requires_an_absolute_relaunch(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)
    response = advice()
    response.update(agent="codex", account="code", model="balanced-code", config_dir=str(tmp_path / 'profile'))
    result = hooks.evaluate("PreToolUse", bash('cd /other; CODEX_HOME=profile codex exec -m balanced-code task'), StubAdvisor(response), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_codex_allows_a_distinct_alias_for_the_advised_account():
    class Aliased(StubAdvisor):
        def status(self):
            value = super().status()
            value["accounts"][1]["aliases"] = ["/profiles/code-alias"]
            return value
    response = advice()
    response.update(agent="codex", account="code", model="balanced-code", config_dir="/home/test/.codex")
    result = hooks.evaluate("PreToolUse", bash('CODEX_HOME=/profiles/code-alias codex exec -m balanced-code task'),
                            Aliased(response), ENV)
    assert result is None


@pytest.mark.parametrize("literal", [";", "&&", "|", "(", "\n"])
def test_quoted_operator_arguments_never_become_commands_or_leak_text(literal):
    import shlex
    advisor = codex_advisor()
    command = "printf '%s\\n' " + shlex.quote(literal) + " codex exec -C /private-text -m expensive"
    assert hooks.evaluate("PreToolUse", bash(command), advisor, ENV) is None
    assert advisor.requests == []


@pytest.mark.parametrize("command", [
    "cat <<'END'\ncodex exec -C /private-text -m expensive\nEND\n",
    "cat <<-END\n\tcodex exec -C /private-text -m expensive\n\tEND\n",
    "cat <<ONE <<'TWO'\ncodex exec -C /private-text -m expensive\nONE\ncodex exec -m expensive\nTWO\n",
    "printf text # comment; codex exec -C /private-text -m expensive\n",
])
def test_heredoc_and_comment_text_is_not_inspected_or_sent_to_advisor(command):
    advisor = codex_advisor()
    assert hooks.evaluate("PreToolUse", bash(command), advisor, ENV) is None
    assert advisor.requests == []


def test_real_codex_launch_after_heredoc_is_still_checked():
    command = "cat <<'END'\nprivate text\nEND\ncodex exec -m expensive task"
    result = hooks.evaluate("PreToolUse", bash(command), codex_advisor(), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"


def test_comment_after_escaped_newline_does_not_turn_text_into_a_launch():
    command = "printf text \\\n# comment; codex exec -C /private-text -m expensive\n"
    advisor = codex_advisor()
    assert hooks.evaluate("PreToolUse", bash(command), advisor, ENV) is None
    assert advisor.requests == []


@pytest.mark.parametrize("command", [
    'cd /nonexistent || codex exec -m balanced-code task',
    'cd /allowed; codex exec -m balanced-code task',
    'cd /allowed && true; codex exec -m balanced-code task',
])
def test_finding_6_uncertain_cd_requires_explicit_relaunch(command):
    advisor = codex_advisor()
    result = hooks.evaluate("PreToolUse", bash(command), advisor, ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert "Relaunch" in result["hookSpecificOutput"]["permissionDecisionReason"]
    assert advisor.requests == []


def test_finding_6_subshell_cd_does_not_change_outer_repository():
    advisor = codex_advisor()
    result = hooks.evaluate("PreToolUse", bash('(cd /allowed); codex exec -m balanced-code task'), advisor, ENV)
    assert result is None
    assert advisor.requests[0]["repo"] == "/repo"


@pytest.mark.parametrize("change", [
    "export CODEX_HOME=/home/test/.codex",
    "CODEX_HOME=/home/test/.codex",
    "unset CODEX_HOME",
])
def test_finding_6_skipped_environment_change_cannot_authorize_another_account(change):
    advisor = codex_advisor()
    command = f"false && {change}; codex exec -m balanced-code task"
    result = hooks.evaluate("PreToolUse", bash(command), advisor, {**ENV, "CODEX_HOME": "/restricted"})
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert "Relaunch" in result["hookSpecificOutput"]["permissionDecisionReason"]
    assert advisor.requests == []
