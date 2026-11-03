# Optional agent steering

Only agents using an installed integration are steered. The menu bar app does
not control arbitrary agent processes. Hooks read the local
[API v1 contract](../docs/api.md), never credentials, prompts or transcripts.
They do not run quota probes or reserve quota.

## Requirements and installation

Python 3.10 or newer must be on PATH. Keep the integration resources at their
installed location. In a source checkout, keep that checkout available: installed
commands point at these scripts. Packaging must ship the complete integrations directory alongside the CLI
or in the app's Resources directory.

After reviewing the changes, a user can opt in with:

```sh
leeway integrations install
leeway integrations uninstall
```

The default command merges hooks into existing Claude profiles found through
cached advisor status (including added accounts and aliases), `~/.claude`,
`CLAUDE_CONFIG_DIR` and managed profiles. If status is unavailable, discovery
warns and falls back to local directories. No missing provider profile is created.
The Codex integration installs `~/.local/bin/leeway-codex`; it never changes Codex
configuration, the real Codex executable, PATH or shell startup files.
Use that wrapper explicitly, or configure an agent runner to invoke it:

```sh
~/.local/bin/leeway-codex exec -m your-model "A task"
```

For one selected Claude profile, or an isolated test home:

```sh
leeway integrations install --provider claude --profile /tmp/example-profile
leeway integrations uninstall --provider claude --profile /tmp/example-profile
```

The selected profile must already exist. Repeat `--profile` to select several.
An explicit profile list replaces discovery. `--provider codex` manages only the
wrapper. `--codex-bin /absolute/path/leeway-codex` changes the wrapper location.
Use the same options for uninstall, especially for profiles no longer discoverable.
`--advisor-url http://127.0.0.1:8799` overrides the loopback port on installation.
Installed commands bind that URL. Reinstall to change it.

Writes are atomic per settings file and preserve file permissions. Reruns replace
only commands carrying Leeway's exact ownership marker. Uninstall preserves
unrelated handlers, shared hook groups and other settings; an unowned wrapper is
never overwritten or deleted. Symlinked settings and wrappers are refused so the
installer does not write beyond the selected file. A partial multi-profile
installation can be resumed by rerunning the same command.

## Policy and decisions

Copy [policy.toml.example](policy.toml.example) to `~/.config/leeway/policy.toml`
and edit account ids, paths, target ranges, reserve accounts, role models and
`over_target` actions. The example is never installed automatically. The advisor
is the single source of policy; hooks contain no account-specific rules.

Targets default to `target_low = 75`, `target_high = 100`. Forecast intervals
wholly below target return go with `headroom_pct`, the percentage points to
target low at the current pace. Overlapping intervals return go. Intervals
wholly above target follow `over_target`; five-hour blocking remains independent.
Status schema 3 carries `under`, `on_target`, `over`, nullable early hours and
severity. Policies containing `ceiling` or `over_ceiling` are rejected; use
`target_low`, `target_high` and `over_target` instead.

Claude hooks:

- `PreToolUse`, matcher `^(Agent|Task|Bash)$`: Agent and legacy Task calls retain
  every input field with only `model` replaced. A deny/wait verdict, or routing to
  another account or app, denies the tool with the reason and retry time.
  To switch, run the shell-quoted relaunch command in the message. For example:
  `CLAUDE_CONFIG_DIR="$HOME/.claude-reserve" claude --model sonnet`.
- `SessionStart`: inject advice and display the current account's server-provided
  over-target status, including stale state. A failed status request
  still preserves available session advice.
- `UserPromptSubmit`: resolve the current profile or alias to its account id and
  block only a deny verdict for that account. Other verdicts become context.
  Unknown current accounts allow with a warning rather than apply another
  account's prompt policy.

These outputs follow Claude Code's documented
[decision control](https://code.claude.com/docs/en/hooks#pretooluse-decision-control).
`updatedInput` contains the complete input object. Omitting `permissionDecision`
on rewrites preserves ordinary permission handling.

Codex checks inspect direct `codex exec -m`/`--model` launches in Claude Bash
calls and argv passed to `leeway-codex`. A nonempty advised model must match the
requested model. Empty advised Codex model means keep the caller's configured
model. When the account or app changes, or the verdict is deny or wait, the call is
refused. Follow the message to retry later or run the supplied command, such as
`CODEX_HOME="$HOME/.codex-reserve" codex exec -m your-model`.
The wrapper preserves arguments, stdin and the child exit status; a refusal
returns 2 without launching Codex. It sends no prompt argument to the advisor.
An optional `LEEWAY_CODEX_COMMAND` selects an explicit real executable.

The Bash parser handles literal `cd`, `-C`/`--cd`, environment assignments,
exports, unsets and multiple direct launches. Quoted separators remain arguments;
comments and here-document bodies are excluded from command inspection.
Dynamic account and repository paths require running the supplied relaunch
command from the repository folder, with literal paths. Put model options
before the prompt. Shell code is never rewritten or executed during inspection.
This is a command admission check, not a shell sandbox. Generated scripts, shell
functions, nested interpreters and calls outside installed hooks/wrappers are
outside its inspection boundary.

Unclassified launches use role `builder` and task class `integration`. Agent
types containing explore, plan, review or evaluat map to their corresponding
roles. The standalone hook runner accepts `--role` and `--task-class`. The raw
Codex runner accepts them before `--`, followed by the original Codex arguments.
Only repository, role, task class, provider and account id reach the advisor.

## Advisor failures

Connection errors, timeouts, malformed responses and incompatible schema versions
allow work and warn on stderr. Hook stdout contains only decision JSON, or is
empty on failure. Each HTTP operation uses a one-second socket timeout, caps its
response at one MiB, ignores proxy settings and never follows redirects. Only
plain HTTP origins on `127.0.0.1` are accepted. Requests use `/v1/status` and
`/v1/advise`.

Retries are stateless. Refreshing or running the same hook twice does not consume
or reserve quota.

## Run the advisor

Start `leeway serve` in a separate terminal before using the integrations. The
menu bar app does not start this HTTP service. Policy changes reload automatically;
valid polling-interval changes reschedule the next refresh. If the advisor cannot
be reached, hooks allow the call and explain how to start it.

## Verification

```sh
python3 -m pytest -q Tests/integrations
```

Tests use temporary homes and profiles, a local loopback stub, a fake Codex
executable and a compiled Swift dispatch harness. They never install into or
launch real Claude/Codex profiles. Packaged-app installation and real agent
runtime verification remain release checks.
