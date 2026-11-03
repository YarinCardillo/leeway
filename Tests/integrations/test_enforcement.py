"""Contract-level enforcement tests with a local advisor double."""

from pathlib import Path

import pytest

from leeway_hooks import hooks


def advice(**changes):
    return dict(schema_version=1, account="current", verdict="go", agent="claude", model="sonnet", effort="medium",
                config_dir="/profiles/current", reason="within quota", retry_at=None, **changes)


class StubAdvisor:
    def __init__(self, response=None):
        self.response = response or advice()
        self.requests = []

    def status(self):
        return {"schema_version": 3, "accounts": [
            {"id": "current", "provider": "claude", "config_dir": "/profiles/current", "aliases": []},
            {"id": "code", "provider": "codex", "config_dir": "/home/test/.codex", "aliases": []}]}

    def advise(self, request):
        self.requests.append(request)
        return self.response


ENV = {"HOME": "/home/test", "CLAUDE_CONFIG_DIR": "/profiles/current"}


def payload(tool="Agent", **fields):
    return {"cwd": "/repo", "tool_name": tool,
            "tool_input": {"prompt": "Build this", "subagent_type": "general-purpose", **fields}}


@pytest.mark.parametrize("tool", ["Agent", "Task"])
def test_agent_rewrites_model_preserving_all_other_input(tool):
    advisor = StubAdvisor()
    data = payload(tool, model="opus", run_in_background=True)
    result = hooks.evaluate("PreToolUse", data, advisor, ENV)["hookSpecificOutput"]
    assert result["updatedInput"] == {**data["tool_input"], "model": "sonnet"}
    assert "permissionDecision" not in result
    assert advisor.requests == [{"repo": "/repo", "role": "builder", "task_class": "integration", "agent": "claude", "account": "current"}]


@pytest.mark.parametrize("kind", ["deny", "wait"])
def test_agent_blocks_when_advisor_refuses(kind):
    response = advice()
    response.update(verdict=kind, reason="weekly target", retry_at="2026-11-04T00:00:00Z")
    result = hooks.evaluate("PreToolUse", payload(), StubAdvisor(response), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert "weekly target" in result["hookSpecificOutput"]["permissionDecisionReason"]
    assert "2026" in result["hookSpecificOutput"]["permissionDecisionReason"]
    assert "Try again after" in result["hookSpecificOutput"]["permissionDecisionReason"]


@pytest.mark.parametrize("changes", [{"verdict": "switch", "config_dir": "/profiles/other"}, {"agent": "codex"}])
def test_agent_denies_routing_that_needs_another_process(changes):
    response = advice()
    response.update(changes)
    result = hooks.evaluate("PreToolUse", payload(), StubAdvisor(response), ENV)
    assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
    assert response["config_dir"] in result["hookSpecificOutput"]["permissionDecisionReason"]


@pytest.mark.parametrize("agent_type, role", [("Explore", "explorer"), ("Plan", "planner"), ("code-reviewer", "reviewer"), ("independent-evaluator", "evaluator")])
def test_agent_maps_specialized_roles(agent_type, role):
    advisor = StubAdvisor()
    hooks.evaluate("PreToolUse", payload(subagent_type=agent_type), advisor, ENV)
    assert advisor.requests[0]["role"] == role


def test_service_failure_allows_and_logs_warning(caplog):
    class Offline:
        def status(self):
            raise OSError("connection refused")

        def advise(self, request):
            raise OSError("connection refused")

    assert hooks.evaluate("PreToolUse", payload(), Offline(), ENV) is None
    assert "could not check limits" in caplog.text


def test_unrelated_tool_does_not_contact_advisor():
    assert hooks.evaluate("PreToolUse", payload("Read"), object(), ENV) is None


@pytest.mark.parametrize("verdict,blocked", [("deny", True), ("wait", False), ("switch", False), ("go", False)])
def test_prompt_blocks_only_deny(verdict, blocked):
    response = advice()
    response["verdict"] = verdict
    output = hooks.evaluate("UserPromptSubmit", {"cwd": "/repo", "prompt": "private text"}, StubAdvisor(response), ENV)
    assert (output.get("decision") == "block") is blocked
    if blocked:
        assert "within quota" in output["reason"]
    else:
        assert output["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit"


class SessionAdvisor(StubAdvisor):
    def status(self):
        return {"schema_version": 3, "generated_at": "now", "accounts": [
            {"id": "current", "config_dir": "/profiles/current", "provider": "claude", "label": "current",
             "seven_day": {"pct": 94}, "forecast": {"range_high": 96}, "stale": False, "status": "over"},
            {"config_dir": "/profiles/other", "provider": "claude", "label": "other",
             "seven_day": {"pct": 99}, "forecast": {"next_round_pct": 100}, "stale": False}], "history": {}}


def test_session_injects_advice_and_warns_on_own_forecast():
    output = hooks.evaluate("SessionStart", {"cwd": "/repo"}, SessionAdvisor(), ENV)
    assert "Use sonnet with medium effort" in output["hookSpecificOutput"]["additionalContext"]
    assert "96" in output["systemMessage"]
    assert "current" in output["systemMessage"]
    assert "other" not in output["systemMessage"]


def test_session_does_not_warn_for_another_accounts_quota():
    env = {**ENV, "CLAUDE_CONFIG_DIR": "/profiles/unlisted"}
    output = hooks.evaluate("SessionStart", {"cwd": "/repo"}, SessionAdvisor(), env)
    assert "systemMessage" not in output


def test_status_failure_keeps_available_session_advice(caplog):
    class BrokenStatus(SessionAdvisor):
        def status(self):
            raise OSError("offline")

    output = hooks.evaluate("SessionStart", {"cwd": "/repo"}, BrokenStatus(), ENV)
    assert "Use sonnet with medium effort" in output["hookSpecificOutput"]["additionalContext"]
    assert "could not check limits" in caplog.text


@pytest.mark.parametrize("event", ["SessionStart", "UserPromptSubmit"])
def test_session_service_failure_allows_with_warning(event, caplog):
    class Offline:
        def status(self):
            raise OSError("connection refused")

        def advise(self, request):
            raise OSError("offline")

    assert hooks.evaluate(event, {"cwd": "/repo"}, Offline(), ENV) is None
    assert "could not check limits" in caplog.text


def test_explicit_role_and_task_class_reach_advisor_without_prompt_text():
    advisor = StubAdvisor()
    hooks.evaluate("PreToolUse", payload(), advisor, ENV, role="evaluator", task_class="design")
    assert advisor.requests == [{"repo": "/repo", "role": "evaluator", "task_class": "design", "agent": "claude", "account": "current"}]


def test_session_warns_on_deduplicated_profile_alias():
    class Aliased(SessionAdvisor):
        def status(self):
            document = super().status()
            document["accounts"][0]["aliases"] = ["/profiles/orca"]
            return document

    output = hooks.evaluate("SessionStart", {"cwd": "/repo"}, Aliased(), {**ENV, "CLAUDE_CONFIG_DIR": "/profiles/orca"})
    assert "96" in output["systemMessage"]


def test_explicit_deny_without_route_fields_still_blocks():
    response = {**advice(), "verdict": "deny", "agent": "", "model": "", "config_dir": "", "reason": "quota exhausted"}
    output = hooks.evaluate("UserPromptSubmit", {"cwd": "/repo"}, StubAdvisor(response), ENV)
    assert output["decision"] == "block"
    assert "quota exhausted" in output["reason"]


def test_prompt_advice_binds_current_account_id_instead_of_another_default():
    advisor = StubAdvisor()
    hooks.evaluate("UserPromptSubmit", {"cwd": "/repo"}, advisor, ENV)
    assert advisor.requests[0]["account"] == "current"


def test_unknown_current_account_allows_and_warns_without_unbound_advice(caplog):
    advisor = StubAdvisor()
    output = hooks.evaluate("UserPromptSubmit", {"cwd": "/repo"}, advisor,
                            {**ENV, "CLAUDE_CONFIG_DIR": "/unlisted"})
    assert output is None
    assert advisor.requests == []
    assert "this call was allowed" in caplog.text


def test_empty_codex_model_keeps_the_callers_configured_model():
    from leeway_hooks.commands import Launch
    value = advice()
    value.update(agent="codex", model="", config_dir="/home/test/.codex")
    assert hooks.codex_denial(Launch(None, ENV, Path('/repo')), value) is None
    assert hooks.codex_denial(Launch("explicit", ENV, Path('/repo')), value) is None


def test_agent_allows_a_distinct_profile_alias_for_the_advised_account():
    class Aliased(StubAdvisor):
        def status(self):
            value = super().status()
            value["accounts"][0]["aliases"] = ["/profiles/alias"]
            return value
    output = hooks.evaluate("PreToolUse", payload(), Aliased(),
                            {**ENV, "CLAUDE_CONFIG_DIR": "/profiles/alias"})
    assert output["hookSpecificOutput"]["updatedInput"]["model"] == "sonnet"


def test_relaunch_keeps_destination_when_effort_or_model_is_empty():
    value = advice()
    value.update(effort="", verdict="switch")
    assert "/profiles/current" in hooks.relaunch(value, ENV)
    assert "/profiles/current" not in hooks.summary(value)
    value.update(agent="codex", model="")
    assert "/profiles/current" in hooks.relaunch(value, ENV)
    assert "/profiles/current" not in hooks.summary(value)

@pytest.mark.parametrize("status,warning", [("under", False), ("on_target", False), ("over", True)])
def test_session_target_verdict_warns_only_when_over(status, warning):
    class TargetAdvisor(SessionAdvisor):
        def status(self):
            snapshot = super().status()
            snapshot["schema_version"] = 3
            snapshot["accounts"][0]["status"] = status
            return snapshot

    output = hooks.evaluate("SessionStart", {"cwd": "/repo"}, TargetAdvisor(), ENV)
    assert ("systemMessage" in output) is warning


@pytest.mark.parametrize("status", ["above_ceiling", "over_limit", "on_target", "under"])
def test_session_does_not_accept_obsolete_or_non_over_status(status):
    class StatusAdvisor(SessionAdvisor):
        def status(self):
            document = super().status()
            document["accounts"][0]["status"] = status
            return document

    output = hooks.evaluate("SessionStart", {"cwd": "/repo"}, StatusAdvisor(), ENV)
    assert "systemMessage" not in output
