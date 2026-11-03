# Unified account order implementation plan

Source: owner revision, 2026-11-03.

**Goal:** One Account order setting controls every account row and the status item's first visible account.
**Architecture:** Reuse AppPreferences.accountOrderMode and manualAccountOrder. Remove active pin state, the separate status picker, detail pin action and obsolete inset logic. Both Settings and a native Account order submenu call the same model action.
**Spec:** docs/spec.md and docs/design.md, revised by this owner request.

## Migration and recovery

A legacy pinned account becomes the first ID in Manual order, preserving the remaining saved order. An existing Manual order without a pin stays Manual; automatic or unset preferences stay risk-first. Encode only the current preference fields. Disabled accounts remain configurable in Settings and omitted from the menu; the status item follows the first menu row, including a row without a reading. Failed saves restore the previous order through the existing save path.

## Tasks

- [x] Replace tests for the superseded independent status selection with failing tests for one shared order, first-row status selection, no-reading first row and enabled-account filtering.
- [x] Add red/green legacy migration and encode-without-pin tests. Remove pin state/actions, detail command and orphaned inset code; simplify the selection to first enabled account.
- [x] Replace the separate Settings picker and menu command with the same Account order setting and two checked native submenu choices. Test synchronization in both directions and absence of detail actions.
- [x] Remove obsolete localized strings, update spec/design/changelog, set app version 0.1.1 build 3 as explicitly requested for the unpublished release.
- [x] Run core, App and integration suites; build signed Release, quit the old PID, open without mock, capture real menu and Settings in light/dark, restore appearance and leave the real app running.
- [x] Reproduce the owner-confirmed hover and drag defects using native hit testing and the hosted NSOutlineView selection delegate. Remove the nil hit test and add native List selection, then run regression tests. Owner will perform the final physical check from a 10-second checklist.
- [x] Final independent review and signed focused commits. No push.


## Verification

App: 140 passed. Core: 111 passed on rerun. Integrations: 156 passed. The first concurrent core run hit the existing policyWatch_SeesAtomicSavesAndKeepsLastValidInterval expectation at PollingDeadlineTests.swift:55; no core code or assertion changed, and the rerun passed.

Native regression evidence: the old row returned nil to AppKit hit testing, and the old hosted NSOutlineView denied selection. Both tests failed before the fixes and passed after native hit testing and List selection were restored. Physical hover, submenu tracking and drag confirmation are delegated to the owner, as explicitly requested; they are not recorded as physically verified by the agent.

The unpublished app version is 0.1.1, build 3, per the owner's instruction. No public tag or published release was overwritten. Independent final review found no blocking issue, including immediate persistence of the normalized legacy preferences.


Real light/dark captures show all three account readings and the single Account order control. The README preview was regenerated with mock data in an isolated Cocoa argument preference domain; persistent presentation preferences were checked unchanged, then the real build was relaunched. Appearance was restored.

Owner manual check (10 seconds): move the pointer across two menu rows and confirm visible neutral hover plus native submenu opening; in Settings choose Manual and drag the last account to the top, then confirm that account is first in the menu and owns the status item. Changing Account order to risk-first from the menu must update the Settings picker and reorder the rows.
