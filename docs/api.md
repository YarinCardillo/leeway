# Leeway local API v1

Specification: `docs/spec.md`.
Contract version: 3.0.0. All percentages are percentage points (0 to 100 for
readings, possibly above 100 for forecasts). Times are RFC 3339 UTC strings.
Unknown readings and reset times are explicit JSON nulls, never zero.

## Transport and compatibility

Bind to `127.0.0.1` only, port 8799 by default (policy `port`). Accept a Host
of `127.0.0.1:<port>` or `localhost:<port>`, reject any Origin header and
other hosts with 403. No CORS. Requests and responses use application/json.
Advice bodies have a maximum of 8192 bytes. Invalid bodies return 400,
oversized bodies 413, unknown routes 404, service failures 500. Error body:
`{"schema_version":1,"error":"safe explanation"}`. Do not expose process output,
credentials, session content, or filesystem errors in error messages.

Clients ignore additional response properties. Removing fields or changing
meaning requires a schema version change. Status and refresh responses use
`schema_version: 3`; advice and errors retain version 1; headroom uses version 2. The URL remains
`/v1` because this contract has not been published. Nullable response fields are present even when null.

## GET /v1/status

Returns the cached status, including current-window history. This endpoint
never runs a Claude probe. CLI `leeway status --json` returns this same shape.
`POST /v1/refresh` explicitly refreshes and returns the same shape; the app
may instead call `UsageService.status(refresh: true)`. Polling defaults to
15 minutes and supports 5, 10, 15, or 30 minutes.

Account `id` is stable, unique across providers, and is the key in `history`
and in policy account references. `label` is the editable user name, never
an email. `config_dir` and `aliases` are local directory paths, not identity
or credential contents. Disabled accounts are excluded. Deduplication compares
provider and resolved config-directory paths, with discovery order choosing the
canonical account. Explicit alternate directories registered in policy appear in
`aliases` when they resolve to that same directory, including symlinks. Their
local histories are combined by timestamp. Distinct directories remain distinct
accounts and are polled separately even if they belong to the same signed-in
identity. Matching quota percentages never imply identity.
`as_of` is the source reading time; age is
`generated_at - as_of`. Failed refreshes retain the last reading with
`stale: true` when the failure is newer than the retained source timestamp.
A valid weekly-only probe is fresh unless an earlier, still-active five-hour
window must be retained. Expired windows do not age a fresh source timestamp.
App `recorded_at` is mapped directly from `as_of`. Events without a valid percentage and reset window are failed
readings, as are percentages outside 0 to 100. Expired windows have null percentage and reset.

`error` is a safe per-account reason for the latest refresh in this service:
`cli_missing`, `timeout`, `not_signed_in`, or `invalid_output`; successful readings
clear it. Cached readings and their timestamps survive a failure. Reasons never
contain stdout, email addresses or authentication details. Detailed reasons are
session-local; SQLite preserves readings and stale failure flags across restarts.
The app and the advisor poll independently.

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "StatusV3",
  "type": "object",
  "required": ["schema_version", "generated_at", "accounts", "history"],
  "properties": {
    "schema_version": {"const": 3},
    "generated_at": {"type": "string", "format": "date-time"},
    "accounts": {"type": "array", "items": {"$ref": "#/$defs/account"}},
    "history": {"type": "object", "additionalProperties": {
      "type": "array", "items": {
        "type": "array", "prefixItems": [
          {"type": "string", "format": "date-time"}, {"type": "number"}
        ], "minItems": 2, "maxItems": 2
      }
    }}
  },
  "$defs": {
    "moment": {"type": ["string", "null"], "format": "date-time"},
    "number": {"type": ["number", "null"]},
    "window": {
      "type": "object", "required": ["pct", "resets_at"],
      "properties": {
        "pct": {"type": ["number", "null"], "minimum": 0, "maximum": 100},
        "resets_at": {"$ref": "#/$defs/moment"}
      }
    },
    "forecast": {
      "type": "object",
      "required": ["seven_day_pct_at_reset", "average_pct_at_reset", "recent_pct_at_reset", "range_low", "range_high", "next_round_pct", "exhausts_at", "confidence"],
      "properties": {
        "seven_day_pct_at_reset": {"$ref": "#/$defs/number"},
        "average_pct_at_reset": {"$ref": "#/$defs/number"},
        "recent_pct_at_reset": {"$ref": "#/$defs/number"},
        "range_low": {"$ref": "#/$defs/number"},
        "range_high": {"$ref": "#/$defs/number"},
        "next_round_pct": {"$ref": "#/$defs/number"},
        "exhausts_at": {"$ref": "#/$defs/moment"},
        "confidence": {"enum": ["none", "low", "medium", "high"]}
      }
    },
    "account": {
      "type": "object",
      "required": ["id", "label", "provider", "config_dir", "registered", "aliases", "plan", "five_hour", "seven_day", "forecast", "source", "stale", "error", "as_of", "target_low", "target_high", "status", "hours_early", "severity"],
      "properties": {
        "id": {"type": "string", "minLength": 1},
        "label": {"type": "string", "minLength": 1},
        "provider": {"enum": ["claude", "codex"]},
        "config_dir": {"type": "string"},
        "registered": {"type": "boolean"},
        "aliases": {"type": "array", "items": {"type": "string"}},
        "plan": {"type": ["string", "null"]},
        "five_hour": {"$ref": "#/$defs/window"},
        "seven_day": {"$ref": "#/$defs/window"},
        "forecast": {"$ref": "#/$defs/forecast"},
        "source": {"enum": ["probe", "codex-log", null]},
        "stale": {"type": "boolean"},
        "error": {"enum": ["cli_missing", "timeout", "not_signed_in", "invalid_output", null]},
        "as_of": {"$ref": "#/$defs/moment"},
        "target_low": {"type": "number", "minimum": 0, "maximum": 100},
        "target_high": {"type": "number", "minimum": 0, "maximum": 100},
        "status": {"enum": ["under", "on_target", "over"]},
        "hours_early": {"type": ["number", "null"], "minimum": 0},
        "severity": {"enum": ["amber", "red", null]}
      }
    }
  }
}
```

`average_pct_at_reset` is the current usage divided by the fraction of the
seven-day window elapsed at `generated_at`. `recent_pct_at_reset` adds the pace
between the first reading at or after 24 hours ago and the latest reading,
carried from `generated_at` to the reset. Recent pace requires at least two
readings spanning at least six hours inside both the current weekly window and
the last 24 hours. A single point, duplicate timestamps, a shorter observed span,
or readings from before the weekly start or the last-24-hour cutoff cannot
qualify. Negative consumption is clamped to zero. Both projections are rounded to one
decimal and never below current usage. Fewer than two weekly readings gives
null projections. Without a qualifying six-hour span, the recent projection and
its deprecated alias are null, confidence is low, and both range bounds equal
the available weekly average. Short bursts cannot raise risk through an
unqualified recent projection; the weekly average still determines status.

`seven_day_pct_at_reset` aliases `recent_pct_at_reset`, including nulls.
There is no third forecast. `range_low` and `range_high` are the minimum and
maximum of available projections, or null when neither is available.
`exhausts_at` uses that same recent pace. `next_round_pct` adds the last five
hours' rise with a one-point minimum. No current reading or a missing or expired
reset gives no forecast. History contains readings since reset minus seven days
and is thinned only for presentation, after calculating forecasts.

Per-account targets default to `target_low: 75`, `target_high: 100`.
Both bounds are in 0 to 100 and `target_low < target_high`.
`status` compares the entire forecast range with this inclusive interval:
`under` when `range_high < target_low`, `over` when `range_low > target_high`,
and `on_target` when the ranges overlap, including equality. With no forecast,
status is neutral `on_target`; this does not assert that the account has a forecast.
Missing readings remain explicit nulls, with `stale: true` when no reading exists.
Measured usage at 95 no longer overrides the weekly range verdict.

For `over`, `hours_early` is `max(0, resets_at - exhausts_at)` in hours,
or null when either timestamp is unavailable. `severity` is `red` above 12
hours, `amber` at or below 12 and when no early exhaustion is predicted.
Other verdicts have null `hours_early` and `severity`. Forecast calculation is unchanged.

Policies accept only `target_low`, `target_high` and `over_target` for target settings.
Obsolete `ceiling` and `over_ceiling` keys are rejected as unknown keys, with
instructions to use the target fields. Reserve-account routing remains available.

## POST /v1/advise

Optional `account`
restricts the preferred account by id or unique label; its configured
reserve account is the next candidate. Optional `agent` restricts the
provider. Paths are matched against policy projects in order, first match
wins. Without project rules every enabled account is eligible. Builder and
reviewer prefer Codex then Claude; other roles use Claude unless `agent` is
explicit. Empty model means keep the Codex model configured by its CLI.

Request JSON Schema:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "AdviceRequestV1", "type": "object",
  "required": ["repo", "role", "task_class"],
  "properties": {
    "repo": {"type": "string", "minLength": 1},
    "role": {"enum": ["builder", "reviewer", "explorer", "planner", "evaluator"]},
    "task_class": {"enum": ["mechanical", "integration", "design"]},
    "agent": {"enum": ["claude", "codex", null]},
    "account": {"type": ["string", "null"], "minLength": 1}
  },
  "additionalProperties": false
}
```

Response JSON Schema:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "title": "AdviceV1", "type": "object",
  "required": ["schema_version", "verdict", "agent", "account", "model", "effort", "config_dir", "reason", "retry_at", "headroom_pct"],
  "properties": {
    "schema_version": {"const": 1},
    "verdict": {"enum": ["go", "switch", "wait", "deny"]},
    "agent": {"enum": ["claude", "codex", ""]},
    "account": {"type": "string"},
    "model": {"type": "string"},
    "effort": {"type": "string"},
    "config_dir": {"type": "string"},
    "reason": {"type": "string"},
    "retry_at": {"type": ["string", "null"], "format": "date-time"},
    "headroom_pct": {"type": ["number", "null"], "minimum": 0}
  }
}
```

A five-hour reading at 95 or more blocks the candidate independently of the
weekly verdict. Weekly steering consumes exactly the account `status`:
`under` and `on_target` allow work; `over` follows `over_target`: `switch`
(default) tries the next eligible account, `block` denies, `warn` allows with
an explicit warning. If all candidates are blocked, `wait` names the earliest
known reset, or `deny` when no reset is known. No eligible account denies.
The first usable candidate returns `go`, or `switch` after an earlier block.
Role/tier routing remains in force.

For an `under` account, advice includes `headroom_pct = target_low - range_high`:
percentage points still needed to reach the target at the current forecast pace.
For `on_target`, `over`, or unknown forecasts, `headroom_pct` is null.
This is separate from CLI headroom, which measures remaining current usage
below the target high. Forecast reasons use the actual reset forecast, never
`next_round_pct`. Unknown readings allow work with an explicit reason.

Default model routing: builder mechanical haiku, integration sonnet,
design sonnet with high effort; reviewer sonnet; explorer mechanical
haiku, otherwise sonnet; planner/evaluator opus. `[roles]` overrides with
`model[:effort]`. Codex uses `codex_model` (empty by default), carrying the
selected effort or medium when unset.

The advisor being unavailable is different from a deny verdict. Integrations
must allow and warn on transport/process failure, as required by the spec.

## Swift interface and CLI

API value types are Codable and Sendable. Swift uses camelCase with
snake_case JSON keys. Dates use Foundation Date, encoded as RFC 3339.
`UsageProvider` exposes async throwing `status(refresh: Bool)` and
`advise(_ request: AdviceRequest)`. `UsageService` implements it with an
injected ProcessRunner and clock. SQLite and source access are serialized.
`StatusDocument.accounts` contains `AccountStatus`; `history` maps account
ids to `[HistoryPoint]` encoded as `[timestamp, percentage]` pairs.

CLI commands: `status [--json]`, `headroom --account <id-or-label> [--json]`,
`advise --repo <path> --role <role> --task-class <class> [--agent <provider>]
[--account <id-or-label>]`, `refresh [--json]`, and `serve`.
Advice always prints JSON. Headroom JSON is
`{"schema_version":2,"account":"id","target_low":75,"target_high":100,"used_pct":20,"headroom_pct":80}`,
with null usage/headroom when unknown; headroom never falls below zero.
`--home <path>` and `--policy <path>` select local fixtures/configuration.
Normal cached commands never probe Claude. `serve` runs periodic refreshes;
it observes atomic policy saves and reschedules a cancellable deadline from the
last refresh when the validated interval changes, without one-second polling.
`refresh` and the app's Refresh now explicitly opt in to a probe.

`leeway integrations install|uninstall` dispatches the optional Python runtime
before loading policy or opening the history database. Installation does not
require quota readings or a valid policy. See [agent integrations](../integrations/README.md).
