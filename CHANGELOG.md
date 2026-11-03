# Changelog

## 0.1.2

- Replace the app target icon with a centered white Leeway wordmark on a sage gradient.
- Generate SF Pro Semibold outlines for the layered macOS 26 icon and macOS 14/15 fallback, with no runtime font dependency.

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
