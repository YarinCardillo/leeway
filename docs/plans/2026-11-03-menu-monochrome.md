# Menu readability and native app icon implementation plan

Source: owner request, 2026-11-03.

**Goal:** Apply the owner's revised menu requirements and use a layered app icon on macOS 26.
**Architecture:** Keep NSStatusItem, NSMenu, NSMenuItem and native submenus. Draw only account presentation when a neutral selection requires it. Keep quota layout in AppModel and use semantic appearance-aware colours. Compile an Icon Composer document with Xcode, retaining older-system icon support.
**Tech Stack:** Swift 6, AppKit, SwiftUI, Xcode 26, Icon Composer.
**Spec:** docs/spec.md and docs/design.md, revised by this owner request.

## Constraints

macOS 14+, native keyboard and VoiceOver menu behaviour, unchanged command selection. No changes to forecasting, storage or protocol. Public artifacts contain no private paths or account names. Signed small commits, no push.

## Review focus

Forecast beyond 100 must not rescale any row. Target ticks must survive overlap and endpoint placement. Highlight must preserve semantic colours in both appearances. Submenus and keyboard navigation must remain native. Finder must use the modern icon without a second container.

## Tasks

### 1. Fixed quota scale and untinted status glyph

- [ ] Replace the old extension-domain tests because the owner changed the requirement. Assert a fixed domain of 100, clamped usage and forecast, and unchanged target fractions across accounts.
- [ ] Run focused tests and observe failures.
- [ ] Implement fixed fractions and two outlined target ticks over all fills. Assert untinted template glyphs for every verdict and severity.
- [ ] Run focused tests. Update spec and design for the revised requirement. Commit with explicit requirement-change rationale.

### 2. Neutral account selection

- [ ] Add failing state tests: account highlight retains label, verdict, caption and meter colours in Aqua and Dark Aqua; commands remain ordinary NSMenuItems.
- [ ] Implement the smallest public-AppKit account drawing exception, using native menu item cells for content and semantic non-emphasized selection colour. Keep tracking, submenus and accessibility on NSMenuItem.
- [ ] Verify state tests, native keyboard/submenu behaviour in the built app and highlighted screenshots in both appearances. Update design exception and commit.

### 3. Layered app icon

- [ ] Create AppIcon.icon with solid graphite background and the existing white target SVG, without a baked mask, margin or shadow.
- [ ] Add it to the Xcode target and retain the macOS 14/15 fallback. Build and inspect compiled icon metadata.
- [ ] Verify Finder list and icon views against Mail and capture the result. Update build documentation and commit.

### 4. Packaged verification and README

- [ ] Run swift test, swift test --package-path App, and python3 -m pytest Tests/integrations.
- [ ] Bump the app release metadata, build signed Release, quit the old PID and open the built app.
- [ ] Capture status icon and highlighted rows in light/dark with short menu rounds.
- [ ] Launch --mock, save a dark menu window screenshot with shadow to docs/images/menu.png, and add a centered README image below the intro.
- [ ] Quit mock, restore appearance and leave the real built app running. Verify signed commits, clean diff and no private data in public artifacts.
