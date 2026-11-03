# Wordmark app icon implementation plan

Source: owner request, 2026-11-03.

**Goal:** Ship the approved sage wordmark icon in 0.1.2, using native macOS 26 rendering and generated macOS 14/15 fallback.
**Architecture:** A Swift/CoreText generator converts SF Pro Semibold glyphs to centered SVG paths. The Icon Composer document uses a full-canvas vertical gradient from #5f7d6b to #3f5a4a behind the white wordmark. The existing Xcode AppIcon target compiles the layered icon and older-system fallback.
**Spec:** docs/spec.md and docs/design.md, revised by this owner request.

- [x] Add failing generation tests for the exact gradient, a white path-only six-letter wordmark and deterministic output without runtime font dependencies.
- [x] Implement scripts/generate_app_icon.swift, regenerate App/Resources/AppIcon.icon and remove its former target glyph. Keep system masking, padding and shadow.
- [x] Update icon requirements, generator instructions, CHANGELOG and release metadata to 0.1.2 with an increased build number.
- [x] Run generation tests, swift test, swift test --package-path App and python3 -m pytest Tests/integrations. Build and verify signed universal Release.
- [ ] Inspect native output at 32, 64 and 128 pixels. Capture real Finder list/icon views and Dock, restoring temporary UI preferences and leaving the real build running.
- [ ] Review the whole branch, make signed commits and never push.
