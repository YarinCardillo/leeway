# Leeway: specification

Status: pre-release specification.

## What it is

A small macOS menu bar utility that answers one question for every AI coding account signed in on this Mac: **how much of this week's quota have I used, and where will I land at the reset?** It also lets people set their own target range per account and exposes the same facts to their agents, which can, if the user opts in, treat Leeway as the authority for steering and model choice.

Leeway does nothing else. It is not an agent manager, not a chat client, not a cost tracker.

## Users

Developers who run Claude Code and Codex, often several accounts on one Mac (personal and work), sometimes many agents in parallel. They want to see at a glance which account is about to run out, and they want their agents to stop or move before it does.

## Product requirements

1. **Accounts.** Discover every Claude Code config dir (default `~/.claude`, any `CLAUDE_CONFIG_DIR`-style dir the user adds, Orca-managed profiles under `~/Library/Application Support/orca/claude-profiles/*/home`) and every Codex home (`~/.codex`, plus added ones). Directories for the same provider that resolve to the same path are shown once. Distinct copies remain separate in 0.1.0. The user names each account (rename in Settings); names never come from emails.
2. **Readings.** Five-hour and weekly used percentage and reset time per account. Claude: the official CLI's `rate_limit_event` from a minimal `claude -p` request (no tools, no session persistence, no setting sources, Haiku), run with that account's config dir. Codex: its own rate-limit records (session logs or CLI), read only. Leeway never reads, copies or stores credentials or tokens, and sends nothing anywhere except what those official CLIs send.
3. **Polling.** Interval configurable (5, 10, 15, 30 minutes; default 15). "Refresh now" in the menu (Cmd-R). A failed reading keeps the last good one and marks it stale with its age.
4. **Forecast.** Two projections of the weekly percentage at the reset: the week's average pace and the last 24 hours' pace, both carried to the reset, never below what is already used. Shown as a range. History kept locally (SQLite in Application Support) for the chart.
5. **Target range.** Per-account `target_low` and `target_high` in percent, default 75 and 100. Both lie in 0 to 100, with low < high. The goal is to use the whole week without running out before reset: finishing low wastes quota, forecasting exhaustion early risks being blocked. Compare the reset forecast range with the inclusive target: **under** when forecast high < target low, **on_target** when the ranges overlap, **over** when forecast low > target high. For over, report hours between forecast exhaustion and reset: amber at or below 12 hours, red above 12. Missing forecasts stay explicitly unknown with a neutral verdict.
6. **Menu bar.** Compact by default, with vector template Phosphor trend-down (under), target (on target), or trend-up (over). Under uses the accent colour; on target remains untinted; over uses system orange for amber or system red for red. Keep the Compact / Percentages option. Pin an account or show the most at risk. Each menu row states its verdict in words, followed by `62% now, 70-84% at reset, target 75-100%` and the reset time. Native submenu detail contains the weekly chart, forecast range and target bounds; unavailable facts are omitted.
7. **Settings window.** Accounts (name, enabled, Target range, reserve account for steering), polling interval, language (System default, English, Italiano), launch at login, updates (automatic checks and Check Now). Target uses a two-handle range control, steps of 5 and minimum gap 5, keyboard and VoiceOver accessible. This is the owner-requested native-only control exception. Return commits an account name and resigns focus; Escape restores the saved name and resigns focus.
8. **Agent interface.** CLI `leeway status --json` and `leeway headroom --account <name>`; local HTTP on 127.0.0.1 only (`GET /v1/status`, `POST /v1/advise`), documented JSON schema, versioned. Status and refresh use schema 3. Advice uses schema 1 with nullable `headroom_pct` for under-target accounts.
9. **Steering, opt-in.** `integrations/` ships ready hooks for Claude Code (PreToolUse on the Agent tool rewrites the subagent model through `updatedInput` or denies; SessionStart injects advice; UserPromptSubmit blocks prompts whose verdict is deny) and Codex (checks `codex exec -m` calls), installed by `leeway integrations install` and removed by `uninstall`. Rules live in `~/.config/leeway/policy.toml`: target ranges, reserve account, model per role, and `over_target` action (warn, switch, block). Under and on-target accounts allow work; under advice reports percentage points needed to reach target low at the current pace. Five-hour blocking remains independent. Advisor down: allow and warn. Only agents with the integration installed are steered.
10. **Updates.** Sparkle 2, signed appcast on GitHub Releases, automatic by default. Homebrew cask in a Homebrew tap.
11. **Distribution.** Developer ID signed, hardened runtime, notarized, stapled. Universal binary. macOS 14+.
12. **Language.** System default, English and Italian strings.

## Non-goals

Cost in currency, token counts per model, any server, any account login inside Leeway, any telemetry, any non-macOS platform in v1.

## Quality bar

Repo small and documented (README with install, privacy, how readings work, agent integration; CHANGELOG; MIT license). Every rule above has a test. Code and copy pass antislop/unslop review, accessibility review (VoiceOver labels, contrast, keyboard), design review side by side with the references in `docs/design.md`, and an independent evaluator that runs the real app. No private names (employers, colleagues, internal hosts) anywhere in the repo.
