# Settings placement implementation plan

Source: owner request, 2026-11-03.

**Goal:** Center the first Settings opening on the active display, restore user placement afterward and keep the whole window visible when displays change.
**Architecture:** Restore the native frame before registering frame autosave, after installing the toolbar. Use a small pure geometry helper with full and visible screen frames to select the pointer's display and fit the window. Keep the current native autosave key and preserve existing valid user positions.
**Spec:** docs/spec.md and docs/design.md.

- [x] Add failing tests for centering on a secondary/negative-origin display, pointer in the menu bar, preserved saved placement, partial/fully offscreen frames and oversized windows.
- [x] Add native regression tests proving restore occurs before autosave registration and opening does not overwrite a valid saved user position.
- [x] Implement placement after toolbar sizing; constrain placement on each opening without recentering valid saved positions.
- [x] Update docs, bump the unpublished build number, run suites and build signed Release.
- [x] Verify first-open and saved-position behavior on the real app, capture a real screenshot, restore normal state and leave the build running. Signed commits, no push.

## Owner follow-up: chart endpoint and four title previews

- [x] Add a failing native Swift Charts layout test proving the reset maps exactly to the right edge of the data plot and the Y labels remain outside that area. Remove scale-range padding that makes the data stop early.
- [x] Inspect the owner-selected Opal, Instagram time and YouTube Studio references through Mobbin deep search, then add temporary debug header variants A (SF Pro Light 34, small secondary percent), B (SF Pro Expanded Regular, reduced percent), C (SF Pro Compressed Semibold, tall/narrow), D (localized forecast sentence, medium verdict-colored interval, based on Opal). Use tabular figures, standard system fonts and no alternate zeros.
- [x] Keep the current default title until the owner chooses. Expose only a temporary native debug preference, not a product Settings control.
- [x] Capture real light-mode detail shots variant-A.png, variant-B.png variant-C.png and variant-D.png, then restore the prior debug preference and leave the real build running. Stop for the owner's choice; remove unchosen variants and the preference only after that choice.

## Owner choice: finalize A

Source: owner request, 2026-11-03. The owner approved A for 0.1.1.

- [x] Make SF Pro Light 34 pt with an 18 pt secondary percent and 10 pt caption the only detail title. Remove alternate variants, the debug preference, narrative strings/helper and its obsolete tests.
- [x] Replace temporary requirements in spec/design with the approved title, and increment the unpublished 0.1.1 build.
- [x] Run core, app and integration suites, build signed Release, capture real detail in light/dark, restore appearance and leave the real app running. Commit signed, never push.
