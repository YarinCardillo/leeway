# Changelog

## Unreleased

- In Compact mode, the menu bar can show a usage percentage beside the icon: the current session while it is open, otherwise the week. Turn it on in Settings, General.

## 0.2.0

- Several copies of Leeway (the app, the command line, agent hooks) now share one set of readings. Only one of them checks usage at a time, so the others never repeat the work or disagree.
- Accounts live in one account book shared by the app and the command line. Every account can be renamed, hidden or removed, and a new `leeway accounts` command lists and edits them.
- A new account is filled in with past usage from its transcripts. These points are marked as estimated until a real reading replaces them.
- The advisor can answer against a landing target you choose, and tells you when to retry once your usage is forecast to fall back under the target. The retry time follows the earlier of the average and recent forecasts, and is checked against the history still available at that time.
- `leeway version --json` reports the version and the data formats the build understands, so apps that bundle the helper can pick the newer compatible copy.
- Menu rows for idle accounts say when Leeway last checked, and the pace line covers every forecast.
- Settings now has a quiet link to the source code on GitHub.
- Fixes: a failed Claude reading is recorded with its reason instead of being lost; an incomplete reading keeps its reason; removing an account that another account uses as a reserve clears that reserve; a rejected policy no longer stops usage checks; an account book changed by another copy is picked up by the app.

## 0.1.2

- New app icon: the Leeway wordmark in white on a sage gradient, in the layered macOS 26 format with fallbacks for macOS 14 and 15.

## 0.1.1

- Read newly enabled accounts immediately and retain typed source failure messages.
- Show visible neutral account selection on pointer hover in both appearances.
- Choose manual account order with native drag and drop, or most at risk first.
- Use one account-order preference in Settings and the menu; the first visible account owns the status item.
- Migrate former pinned accounts to the first position in Manual order.
- Keep Settings at a standard size with scrolling inside each tab.
- Keep compact menu bar glyphs monochrome using system template rendering.
- Preserve readable account colours on neutral menu selection.
- Use the same 0-100% meter scale for every account with two visible target ticks.
- Use a layered app icon on macOS 26 with generated fallback icons for macOS 14 and 15.

## 0.1.0

- Read weekly and five-hour usage for Claude Code and Codex accounts.
- Show forecasts, target ranges and usage history in the menu bar.
- Configure accounts and targets in English or Italian.
- Provide a local API, CLI and optional agent hooks.
