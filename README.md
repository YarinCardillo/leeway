# Leeway

Claudy with a chance of rate limits.

Leeway is a macOS menu bar app for Claude Code and Codex. For every account
signed in on your Mac it shows how much of this week's quota you have used,
where you will land at the reset, and whether that falls inside the target
range you chose.

## Install

Requires macOS 14 or later, and Claude Code or Codex already signed in.

```sh
brew install --cask yarincardillo/tap/leeway
```

Or download `Leeway-<version>.dmg` from
[Releases](https://github.com/YarinCardillo/leeway/releases/latest) and drag
Leeway to Applications. The app is signed and notarized, and updates itself
through Sparkle. Turn automatic updates off in Settings, Updates.

The cask also links the `leeway` command line tool. With the DMG, link it into
any folder on your PATH:

```sh
ln -s /Applications/Leeway.app/Contents/Helpers/leeway ~/.local/bin/leeway
```

## How it reads your quota

Leeway finds the default `~/.claude` and `~/.codex` folders and managed Claude
profiles. Add other folders, rename accounts, or hide them in Settings.

- Claude: a minimal request through the official `claude` CLI (Haiku, no
  tools, no saved session) returns the current rate limits. Each reading
  uses a very small amount of quota.
- Codex: Leeway reads the rate limit records Codex already writes locally. No
  request is sent.

Readings repeat every 15 minutes by default (5 to 30 in Settings), or on
Refresh Now. A failed reading keeps the last good one, marks it out of date
and says why.

## Forecast and target

The forecast carries two paces to the reset: this week's average and the last
24 hours. Leeway compares that range with your target, 75-100% by default:

- **Room to use**: the whole forecast is below the target.
- **On target**: the forecast and the target overlap.
- **Over target**: the whole forecast is above the target. Orange when you would
  run out up to 12 hours before the reset, red when earlier.

The forecast is an estimate, not a guarantee.

## Privacy

Leeway never reads, copies or stores credentials, and has no telemetry. History
stays in `~/Library/Application Support/leeway/history.sqlite`. The only network
traffic is what the official Claude CLI sends and the update check.

## Agents

Agents can ask Leeway before they spend:

```sh
leeway status --json
leeway headroom --account Work
```

`leeway serve` exposes the same data on `127.0.0.1` only. Optional hooks for
Claude Code and Codex can warn, switch to a reserve account or block when an
account is over target. Nothing is steered unless you install them:

```sh
leeway integrations install
```

Rules live in `~/.config/leeway/policy.toml`; start from
[policy.toml.example](integrations/policy.toml.example). Details in the
[integration guide](integrations/README.md) and the [API](docs/api.md).

## Uninstall

Run `leeway integrations uninstall` if you installed the hooks, then
`brew uninstall --cask leeway` or move Leeway to the Trash. History and
`~/.config/leeway` stay until you delete them.

## Build from source

Xcode 16 or later with Swift 6. Integration tests need Python 3.10 or later.

```sh
xcodebuild -project App/Leeway.xcodeproj -scheme Leeway -configuration Debug \
  -derivedDataPath .build/xcode build
open .build/xcode/Build/Products/Debug/Leeway.app

swift test
swift test --package-path App
python3 -m pytest Tests/integrations
```

[Specification](docs/spec.md), [design](docs/design.md),
[core and CLI](docs/core.md), [release process](docs/release.md),
[changelog](CHANGELOG.md). MIT license.
