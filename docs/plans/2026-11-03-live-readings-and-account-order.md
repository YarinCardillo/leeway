# Live readings, account hover and ordering implementation plan

Source: owner feedback, 2026-11-03.

**Goal:** Fix real account reads and typed errors, visible neutral hover, and configurable account order.
**Architecture:** Diagnose the real readers and application mapping before changing them. Preserve NSMenu tracking and native submenu behavior. Keep persisted ordering in AppModel, independent of status-item account selection; use a native SwiftUI List with onMove in Accounts settings.
**Tech Stack:** Swift 6, AppKit, SwiftUI, SQLite, macOS 14+.
**Spec:** docs/spec.md and docs/design.md, extended by this owner request.

## Constraints and recovery

No credential access by Leeway, no private paths or account names in public fixtures. Keep last good usage after a failed read and show a safe typed reason. No database schema changes. Ordering saves atomically through the existing preference save path; failed saves restore the previous order. Retrying/relaunching must retain the order without duplicating accounts. Manual ordering does not affect the status item's existing most-at-risk behavior.

## Tasks

### 1. Real readings and typed failures

- [x] Compare live compiled CLI status and refresh with application state and rate-limit-only session records. Trace the first failing boundary.
- [x] Add a failing regression for each confirmed cause, including enable/refresh and source-to-menu error propagation as applicable.
- [x] Apply the minimum fix, run reader/core/adapter tests and confirm the real reader returns readings or specific typed failures.

### 2. Visible neutral hover

- [x] Reproduce pointer hover, distinct from keyboard highlight, in the signed real app.
- [x] Add a failing state test and implement native tracking invalidation plus visible non-emphasized silver selection in both appearances.
- [ ] Complete the physical pointer hover/drag check when the Mac is idle. State tests cover pointer entry/exit, keyboard precedence and submenu retention; command drawing is unchanged.

### 3. Account ordering

- [x] Add red/green model tests for manual order, native move offsets, persistence/relaunch, missing/new accounts, risk mode, independent status-item selection and failed saves.
- [x] Add backward-compatible ordering preferences, model actions and stable sorting.
- [x] Add an Accounts order picker (manual or most at risk first) and a native reorderable List. Retain the existing per-account settings controls.
- [x] Localize controls in English and Italian and update spec/design.

### 4. Standard Settings size and shared status selection

- [x] Replace content-driven window sizing with a standard 560 by 500 pt initial content size, minimum 520 by 440, preserving user resizing across tabs. Long Forms scroll internally. Reset the previous content-driven saved frame once.
- [x] Add red/green tests for initial/minimum sizing and stable frame across large and small pane preferred sizes.
- [x] Expose Menu bar account in Settings using the existing AppPreferences.pinnedID and model.pin action. Test immediate shared menu/Settings state in both directions. Keep row ordering separately labelled.

### 5. Verify and deliver

- [x] Bump affected release metadata and record the fixes in the changelog.
- [x] Run swift test, swift test --package-path App and python3 -m pytest Tests/integrations.
- [x] Build signed universal Release, quit the prior PID and open the build without mock.
- [x] Verify real readings in light/dark captures, shared menu/Settings status selection, stable Settings frame and native internal scrolling. Restore the original appearance.
- [ ] Confirm native drag reordering and pointer hover physically on the idle Mac. The native List is present; model move, persistence and failure behavior are tested.
- [x] Independent final review, signed focused commits, no push, leave real app running.


## Verification results

Both real readers returned readings through the compiled CLI refresh. The app's missing rows were retained placeholders from previously disabled accounts, and its manual Refresh Now immediately restored both readings. Recent active Codex session records were valid; the archive-removal hypothesis was not supported.

Core: 111 tests passed. App: 134 tests passed. Integrations: 156 tests passed. Signed universal Release 0.1.2 (3) passed strict signature verification and remains running without mock. Independent review findings received failing regressions and fixes, then passed re-review.

The real menu was captured in both appearances. Settings Accounts and General have the same 560 by 588 pt outer frame (500 pt content), and native internal scrolling was verified through accessibility. Choosing a pinned account in Settings and then automatic selection from the menu updated the same preference immediately, without changing manual row order.

Physical drag/hover verification awaits a brief idle interval on the shared Mac. It is not recorded as passed. No screenshots containing real account names are committed publicly.
