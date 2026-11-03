# Leeway app

macOS 14 or later, Swift 6, Xcode 16 or later. Sparkle 2 is the only remote dependency.

## Build

```sh
xcodebuild -project App/Leeway.xcodeproj -scheme Leeway -configuration Debug \
  -derivedDataPath .build/xcode build
swift test --package-path App
```

Debug builds use ad hoc signing. Release builds target arm64 and x86_64 with
Developer ID signing and require `DEVELOPMENT_TEAM=YOUR_TEAM_ID`. Use [`scripts/release.sh`](../scripts/release.sh) for signed distribution.
See [release.md](../docs/release.md) for notarization, packaging and update signing. The displayed version comes from bundle metadata.

`AppCore` links the root LeewayCore package. To use another checkout, set
`LEEWAY_CORE_PACKAGE` to that checkout's location before building or testing.

## Run

```sh
open .build/xcode/Build/Products/Debug/Leeway.app
open -n .build/xcode/Build/Products/Debug/Leeway.app --args --mock
```

Normal launches use LeewayCore and local SQLite history. `--mock` supplies
synthetic readings. Polling starts at launch, before opening the menu. Finder
launches add standard CLI installation directories to PATH; custom installations
must already be in the inherited PATH.

After a signed build, `App/scripts/check-launch.sh /path/to/Leeway.app` verifies
the signature and checks that launch through `open` stays alive. It leaves the
app running with mock data for inspection.

## How it works

`UsageProvider` separates presentation from reading and storage. The app never
handles credentials. Display choices persist in UserDefaults; account names,
enabled state, target ranges, reserves and polling use `~/.config/leeway/policy.toml`.
Settings validates and atomically replaces that file, preserves supported routing
rules, merges unrelated external edits and rejects conflicts. Comments and
formatting are replaced. Failed writes restore the saved choices.

Failed readings retain the last good data and mark it out of date. Dates and
percentages follow the selected language. Login registration uses SMAppService
and reports errors or required system approval.

The menu uses NSMenu and native submenus, with a hosted Swift Charts view on macOS 14. Native selection and checkmarks follow system appearance. Compact mode defaults to a Phosphor vector template icon; General can enable percentages. See the interaction contract in [design.md](../docs/design.md).
Arrow keys and Return operate the menu; Command-R refreshes, Command-comma opens
Settings, and Escape closes detail before the menu. The chart provides a VoiceOver
audio graph with measured usage, both forecasts and the target bounds.

## Known limits

Failed readings carry a safe localized reason: missing CLI, timeout, sign-in
required or invalid quota output. The last successful reading stays visible. The app does
not run the HTTP advisor; start `leeway serve` for installed agent integrations.

Updates require a valid HTTPS feed and a public key, supplied at build time as
`LEEWAY_UPDATE_FEED_URL` and `LEEWAY_UPDATE_PUBLIC_KEY`. Without both, updates
are not set up, and Check Now explains this explicitly. Both Debug and Release
inherit the checked-in feed and public key. Automatic checks and downloads default
to on; successful updates require accessible, signed release assets. The app
exposes no channel selection.

App icon assets, a published appcast, macOS 14 interaction and end-to-end
VoiceOver checks remain distribution requirements. Local release packaging and
notarization are covered by the release pipeline.
