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
`.claude` and `.codex` directories, Grok Bot's data folder
(`~/Library/Application Support/Grok Bot`), added policy directories, the active
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
six recent rollout tails of 512 KiB each. Grok Bot readings come from its
cached weekly usage slice only, at most 64 KiB, and fill only the weekly window. `serve` refreshes immediately and
at the configured interval, and exposes the [v1 JSON API](api.md).
`--home` and `--policy` may appear before or after the command. An alternate
home changes defaults, policy lookup, discovery root, and database path;
explicit config-directory environment variables remain explicit sources.

SQLite history lives at
`~/Library/Application Support/leeway/history.sqlite`. Writes are atomic and
idempotent per source account and timestamp. A source failure retains the
last successful observation and persists stale state. The next successful
reading clears it. Missing or expired windows are null. Claude readings
older than the polling interval are stale; Codex log and Grok Bot cache readings retain their
source time and are not stale merely because no new request has been made.

The database carries its layout in SQLite's `user_version` (`SnapshotStore.schemaVersion`,
2 today: 1 added failure reasons and refresh requests, 2 added the `estimated` column on snapshots). Opening migrates an older file in place and stamps it. A file stamped higher than
the build knows is refused with `CoreError.storeNewerThanBinary` before any change, so an
older helper cannot corrupt data a newer one wrote. Raise the number with every migration.

Estimated history: the first time an account is read, `UsageService` asks `Backfill` to
build the current week from the account's transcripts (`TranscriptUsage` reads timestamps
and token counts only) and stores the points with `estimated = 1` in the same transaction
as the reading. They never count as readings (`latest`, `hasReadings`), and
`Forecaster.settled` drops them once three real readings exist in the window.

`PollLock` (an `flock` on `poll.lock` beside the history database) keeps one polling
process at a time. `UsageService` given a lock reads quota only while it holds it;
otherwise it serves the store and, on `refresh`, records a request in the store's
`refresh_requests` table for the holder. See `docs/api.md` for the `poller` field.

Each discovered source has observations in SQLite. Sources are deduplicated only
by provider and resolved config-directory path. Explicit policy aliases that
resolve to the canonical directory share its combined history. Distinct directory
copies stay separate, even for the same signed-in identity or identical quotas.

`AccountStatus.error` carries a safe typed refresh reason to the app. The reason is
stored with the failure flag, so every process sharing the history shows it; failures
preserve the last good SQLite reading and its timestamp.
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

`AccountBook` (with `AccountBookFile` for locked edits and `AccountsCommand` for the `accounts` verbs)
is the one account list for every client; see "The account list" in `api.md`. The Leeway app keeps
no account preferences of its own: folders it added and its manual order moved into the book once
(the book's `app_preferences_imported` flag), while names, targets and reserves still live in the policy file.
`TargetDiscovery.discover` takes the book and skips removed and hidden folders.

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
