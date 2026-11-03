# Releasing Leeway

Requires macOS, Xcode with its command-line tools, Python 3, Git and `gh` for the
manual publication step. Run from a clean release worktree. Nothing in the
pipeline pushes, creates repositories or publishes releases. The script refuses
tracked changes and untracked files before creating outputs, then rechecks the
worktree and source commit after the builds and before signing. Ignored build
outputs do not count as source changes.

## Release inputs

`App/Version.xcconfig` is the only source of the human version and build number.
Update `LEEWAY_RELEASE_VERSION`, increase `CURRENT_PROJECT_VERSION` for every
build distributed to anyone, and add an exact matching section to `CHANGELOG.md`.
Supported versions are `MAJOR.MINOR.PATCH` and `MAJOR.MINOR.PATCH-rc.N`, `-beta.N`
or `-alpha.N`. Build numbers increase across all channels. Settings reads the
version from the built bundle. The CLI keeps its lowercase `leeway` name.

The xcconfig also supplies the HTTPS feed URL and public EdDSA key. Xcconfig
URLs use `https:/$()/` to avoid interpreting `//` as a comment. The effective
URL is `https://github.com/YarinCardillo/leeway/releases/latest/download/appcast.xml`.
No runtime GitHub access token is embedded in the app.

The machine must already have a Developer ID Application certificate with its
private key, a validated `leeway-notary` keychain profile, and Sparkle's private
EdDSA key under account `leeway`. The script only looks up the existing public
key and uses the private key through Sparkle's tools. It never creates keys or
exports credentials. Override the certificate selection with
`LEEWAY_SIGN_IDENTITY` if more than one Developer ID Application identity exists;
`LEEWAY_NOTARY_PROFILE` selects another existing notarization profile.

## Cut a local release

1. Run `python3 -m unittest discover -s Tests/release -v`, `swift test` and
   `swift test --package-path App`. Commit the release inputs with a signed commit.
2. After the first build, obtain the **current published appcast**, which must
   contain stable and beta history. For example, download `appcast.xml` from the
   latest stable release with `gh release download --repo YarinCardillo/leeway
   --pattern appcast.xml --dir /path/to/previous-feed`. Set
   `LEEWAY_PREVIOUS_APPCAST=/path/to/previous-feed/appcast.xml`. A local copy is
   reused from `.build/releases/appcast.xml` when no override is supplied. Check
   that this copy includes any newer prereleases before using it. A missing feed
   is allowed only for build 1. The build must exceed every existing feed item.
3. Run `scripts/release.sh 0.1.0` (substitute the version from xcconfig).
   It builds Release app and CLI for arm64 and x86_64, bundles the integration
   runtime, signs every nested Mach-O and code container with hardened runtime
   and a secure timestamp, then signs the outer app. The empty entitlement file
   deliberately grants no hardened-runtime exceptions. Leeway is not sandboxed.
   Sparkle 2.10.1's bundled services also require no extra entitlements.
4. The script submits an intermediate ZIP using
   `xcrun notarytool ... --keychain-profile leeway-notary`. After acceptance it
   staples and verifies the **app**, creates a fresh final ZIP, extracts that ZIP
   and repeats codesign, Gatekeeper and ticket checks on the extracted app.
   ZIP files cannot be stapled themselves. The ticket travels inside `Leeway.app`.
5. A simple signed, separately notarized and stapled DMG is also produced.
   Set `LEEWAY_CREATE_DMG=0` to omit the optional DMG. Sparkle always uses the ZIP.
6. Sparkle `sign_update --account leeway` signs and verifies the final ZIP;
   `generate_appcast` preserves existing feed items and embeds the changelog
   notes. The generator labels prereleases `beta`; stable entries have no
   channel. The app has no channel selector and uses Sparkle's default stable
   channel, so those prereleases are not offered by its updater. The complete feed is signed and verified, and the
   app requires feed signatures and verification before archive extraction.
7. Inspect `.build/releases/<version>/`: ZIP, optional DMG, `appcast.xml`,
   `release-notes.md`, `SHA256SUMS`, `leeway.rb`, `source-commit.txt`, logs and
   `publish-draft.sh`. The script updates `Casks/leeway.rb` with the version and
   SHA256 of the final ZIP. Review and commit that change after checking the
   archive. Launch the signed app with `open -n /path/to/Leeway.app --args --mock`; test the bundled CLI with
   `Leeway.app/Contents/Helpers/leeway --help`. Integrations additionally require
   Python 3.10 or newer on the user's machine, as documented in integrations/.

The script refuses to overwrite a version's existing output. On failure, preserve
that directory and inspect `logs/pipeline.log` and the corresponding build log.
Notarization JSON retains the submission ID. If the 30-minute wait expires, query
or wait for that existing submission with `xcrun notarytool info <id>` or
`xcrun notarytool wait <id> --keychain-profile leeway-notary`, and retrieve the
service log with `xcrun notarytool log <id> --keychain-profile leeway-notary
/path/to/notary-log.json`. Do not blindly resubmit. A failed, undistributed
attempt can be moved aside before rebuilding. Once anyone has consumed a build,
use a new version and build number. Rebuilding cannot overwrite a published tag.

The checked-in 0.1.0 cask keeps the previous local archive checksum until
`scripts/release.sh 0.1.0` creates the final archive and replaces it. Do not
distribute the cask before that step.

## Manual publication and future Homebrew tap

Review `publish-draft.sh`. It contains the exact `gh release create` command,
with `--draft`, a source commit, notes and explicit assets. It also uses
`--prerelease` for release candidates. The pipeline prints it but never runs it.
The source commit must exist on GitHub before you manually create the draft.
Creating the draft and publishing it are separate operator actions.

The repository is currently private. The unauthenticated Sparkle URL cannot
serve updates to end users while the repository is private. GitHub's
`releases/latest` also excludes drafts and prereleases: the first RC does not
make that URL live. Before enabling public distribution, make the release
assets accessible and publish a stable release containing the cumulative feed.
Keep the cumulative feed asset on the latest stable release current. Prerelease
items may remain in the feed, but the app does not opt into their channel. Re-sign
the feed after every edit. Never replace an already distributed binary or reuse its version.

`Casks/leeway.rb` is prepared for a future `YarinCardillo/homebrew-tap` repository.
It pins the ZIP checksum, installs `Leeway.app`, links its bundled CLI, sets
`auto_updates true`, and requires macOS Sonoma or newer. Copy it into that tap
only when explicitly authorized to create or update the tap. The cask download
will require public release assets. The pipeline updates the local cask; it never
publishes the tap.

## Back up the Sparkle signing key

Use Sparkle's existing tools after package resolution:

```sh
xcodebuild -resolvePackageDependencies -project App/Leeway.xcodeproj \
  -scheme Leeway -derivedDataPath .build/xcode
SPARKLE_BIN=.build/xcode/SourcePackages/artifacts/sparkle/Sparkle/bin
umask 077
"$SPARKLE_BIN/generate_keys" --account leeway -x /encrypted-volume/leeway-sparkle-private-key
```

Do this manually with an encrypted backup volume mounted. Do not print the file,
put it in Git, attach it to a release, or store it next to public artifacts.
Keep an offline encrypted backup and a second controlled recovery copy. Restore
on a replacement Mac using `generate_keys --account leeway -f <backup-file>`;
compare the existing public key using `generate_keys --account leeway -p`.
Do not run key generation to replace a missing key silently. For key rotation,
follow [Sparkle's key rotation procedure](https://sparkle-project.org/documentation/key-rotation/)
so existing installations can authenticate the transition.

## Rotate the notarization API key

The API key used for Apple's notarization service is distinct from Sparkle's
EdDSA signing key and from the Developer ID certificate.

1. Create a replacement key in App Store Connect with access sufficient for
   notarization, and download its `.p8` file once to an encrypted, private location.
2. Store and validate it interactively in a temporary keychain profile:
   `xcrun notarytool store-credentials leeway-notary-next`. Follow Apple's prompts
   for the API private-key path, key ID and issuer ID. Do not paste private-key
   contents or credentials into shell arguments, logs, documentation or Git.
3. Validate access with `xcrun notarytool history --keychain-profile
   leeway-notary-next` and perform a local notarization with
   `LEEWAY_NOTARY_PROFILE=leeway-notary-next` before revoking the old key.
4. Update `leeway-notary` interactively with `xcrun notarytool store-credentials
   leeway-notary`, then verify that profile again. Revoke the previous API key in
   App Store Connect only after the replacement works. Update encrypted recovery
   copies and remove obsolete local key files according to your backup policy.

For individual API keys, follow Apple's current notarytool help regarding issuer
requirements. Never recreate the Developer ID certificate or rotate Sparkle's
key as a side effect of rotating the notarization API key.

References: [Apple notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
[Sparkle publishing](https://sparkle-project.org/documentation/publishing/),
[Sparkle signing nested services](https://sparkle-project.org/documentation/sandboxing/#code-signing).
