# LeewayCore and Leeway CLI

The package targets Swift 6 and macOS 14 or later. Core uses Foundation,
Darwin, and the system SQLite library, with no package dependencies.

```sh
swift test
swift build -c release
.build/release/leeway help
```

## Policy

The optional user policy is `~/.config/leeway/policy.toml`. No policy means
all discovered enabled accounts may serve every repository. Account names
come from `label`, never account emails. Discovery checks the default
`.claude` and `.codex` directories, added policy directories, the active
`CLAUDE_CONFIG_DIR` and `CODEX_HOME`, and managed Claude profiles described
in the spec. It checks file structure without opening credential files.

```toml
port = 8799
poll_minutes = 15
codex_model = ""

[[accounts]]
id = "primary"
provider = "claude"
label = "Primary"
config_dir = "~/.claude"
enabled = true
target_low = 75
target_high = 100
reserve_account = "reserve"
over_target = "switch"

[[accounts]]
id = "reserve"
provider = "claude"
label = "Reserve"
config_dir = "~/.claude-reserve"
target_low = 75
target_high = 100

[[accounts]]
id = "codex-default"
provider = "codex"
label = "Codex"
config_dir = "~/.codex"
target_low = 75
target_high = 100

[roles]
planner = "opus"
reviewer = "sonnet"
builder = "sonnet"

[[projects]]
name = "example"
paths = ["~/projects/example"]
claude = ["primary", "reserve"]
codex = ["codex-default"]

[default]
claude = ["primary"]
codex = ["codex-default"]
```

Only include added directories that exist and have been signed in through
their official CLI. Configured ids must be unique across providers. A reserve
must name another configured account. Disabled directories also suppress
automatic discovery of that directory. Project paths match whole directory
boundaries, first project wins. Account lists name ids in preference order;
an omitted provider list permits all its enabled accounts and an empty list
permits none. A reserve remains subject to project and provider restrictions.

Target bounds accept 0 to 100, default 75 and 100, with low less than high. Polling accepts 5, 10, 15, and 30
minutes, default 15. `over_target` is `switch` by default; `warn` permits
weekly over-target work with a reason; `block` denies. A full five-hour
window still blocks regardless of the weekly action. `model[:effort]` role
overrides select Claude models; `codex_model` selects the
Codex model, or an empty value preserves its own CLI configuration.

The parser accepts the policy's TOML subset: integer and finite decimal
numbers, booleans, double-quoted strings with JSON escapes, single-quoted
literal strings, string arrays (including multiline arrays and trailing
commas), `[roles]`, `[default]`, `[[accounts]]`, and `[[projects]]`. Comments
are supported outside strings. Unknown keys, duplicate keys/tables, other
TOML constructs, and invalid types are errors, never silently ignored rules.

## Reading and persistence

```sh
leeway refresh --json
leeway status --json
leeway headroom --account Primary
leeway advise --repo ~/projects/example --role builder --task-class integration --agent claude
leeway serve
```

`refresh` opts into official Claude requests. `status`, `headroom`, and
`advise` never probe Claude. Codex limit records are read only, from at most
six recent rollout tails of 512 KiB each. `serve` refreshes immediately and
at the configured interval, and exposes the [v1 JSON API](api.md).
`--home` and `--policy` may appear before or after the command. An alternate
home changes defaults, policy lookup, discovery root, and database path;
explicit config-directory environment variables remain explicit sources.

SQLite history lives at
`~/Library/Application Support/leeway/history.sqlite`. Writes are atomic and
idempotent per source account and timestamp. A source failure retains the
last successful observation and persists stale state. The next successful
reading clears it. Missing or expired windows are null. Claude readings
older than the polling interval are stale; Codex log readings retain their
source time and are not stale merely because no new request has been made.

Each discovered source has observations in SQLite. Sources are deduplicated only
by provider and resolved config-directory path. Explicit policy aliases that
resolve to the canonical directory share its combined history. Distinct directory
copies stay separate, even for the same signed-in identity or identical quotas.

`AccountStatus.error` carries a safe typed refresh reason to the app. Reasons
are session-local; failures preserve the last good SQLite reading and its timestamp.
`serve` watches the policy directory for atomic saves and replaces its cancellable
polling deadline when the validated interval changes. Invalid policy updates keep
the last valid policy.

## App and integration boundaries

The app implements or consumes the Sendable `UsageProvider` protocol:

```swift
func status(refresh: Bool) async throws -> StatusDocument
func advise(_ request: AdviceRequest) async throws -> Advice
```

`UsageService` is an actor. Its constructor takes `home`, `policy`, `store`,
`runner`, `environment`, and an optional injected clock. Use
`SnapshotStore(path:)` with the app's local database path and
`SystemProcessRunner()` for production. `Forecast`, `UsageWindow`,
`AccountStatus`, and `StatusDocument` have public initializers for app mocks.
Use `JSONCodec` for the documented snake_case fields and explicit nulls.

The executable dispatches `integrations` before loading policy or quota data.
The runtime receives literal arguments without a shell and preserves its exit
status. It is found in app Resources, `../share/leeway/integrations` relative
to the executable, or a source checkout. `LEEWAY_INTEGRATIONS_EXECUTABLE` can
select another installed runtime. The advisor controls only agents whose
integration is installed; unavailable transport allows work and warns.

## Verification boundaries

Tests inject all quota probe runners. Real process tests use harmless system
commands only. Loopback transport is tested with actual local HTTP requests.
Real account authentication, CLI compatibility, app packaging, signing,
notarization, and UI behavior require the later app/release verification.
