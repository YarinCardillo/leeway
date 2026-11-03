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

- [ ] Compare live compiled CLI status and refresh with application state and rate-limit-only session records. Trace the first failing boundary.
- [ ] Add a failing regression for each confirmed cause, including enable/refresh and source-to-menu error propagation as applicable.
- [ ] Apply the minimum fix, run reader/core/adapter tests and confirm the real reader returns readings or specific typed failures.

### 2. Visible neutral hover

- [ ] Reproduce pointer hover, distinct from keyboard highlight, in the signed real app.
- [ ] Add a failing state test and implement native tracking invalidation plus visible non-emphasized silver selection in both appearances.
- [ ] Verify mouse movement, keyboard selection and submenu retention without modifying command selection.

### 3. Account ordering

- [ ] Add red/green model tests for manual order, native move offsets, persistence/relaunch, missing/new accounts, risk mode, independent status-item selection and failed saves.
- [ ] Add backward-compatible ordering preferences, model actions and stable sorting.
- [ ] Add an Accounts order picker (manual or most at risk first) and a native reorderable List. Retain the existing per-account settings controls.
- [ ] Localize controls in English and Italian and update spec/design.

### 4. Standard Settings size and shared status selection

- [ ] Replace content-driven window sizing with a standard 560 by 500 pt initial content size, minimum 520 by 440, preserving user resizing across tabs. Long Forms scroll internally. Reset the previous content-driven saved frame once.
- [ ] Add red/green tests for initial/minimum sizing and stable frame across large and small pane preferred sizes.
- [ ] Expose Menu bar account in Settings using the existing AppPreferences.pinnedID and model.pin action. Test immediate shared menu/Settings state in both directions. Keep row ordering separately labelled.

### 5. Verify and deliver

- [ ] Bump affected release metadata and record the fixes in the changelog.
- [ ] Run swift test, swift test --package-path App and python3 -m pytest Tests/integrations.
- [ ] Build signed universal Release, quit the prior PID and open the build without mock.
- [ ] Verify real readings, pointer hover and Accounts ordering. Save short light/dark screenshot rounds and restore the original appearance.
- [ ] Independent final review, signed focused commits, no push, leave real app running.
