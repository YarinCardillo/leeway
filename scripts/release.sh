#!/bin/bash
# Build local release artifacts. Publication is deliberately a printed command.
set -euo pipefail
umask 022
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
if [[ $# != 1 ]]; then
    printf 'Usage: scripts/release.sh <version>\n' >&2
    exit 64
fi
VERSION=$1
require_clean_worktree() {
    local status
    status=$(git status --porcelain=v1 --untracked-files=all)
    [[ -z "$status" ]] || { printf 'Release requires a clean worktree, including untracked files.\n' >&2; exit 1; }
}
require_clean_worktree
SOURCE_COMMIT=$(git rev-parse HEAD)
BUILD=$(python3 scripts/release_metadata.py version App/Version.xcconfig "$VERSION")
NOTES=$(python3 scripts/release_metadata.py notes CHANGELOG.md "$VERSION")
IDENTITY=${LEEWAY_SIGN_IDENTITY:-Developer ID Application}
PROFILE=${LEEWAY_NOTARY_PROFILE:-leeway-notary}
ACCOUNT=leeway
REPO=YarinCardillo/leeway
DERIVED="$ROOT/.build/xcode"
RELEASES="$ROOT/.build/releases"
OUT="$RELEASES/$VERSION"
PREVIOUS=${LEEWAY_PREVIOUS_APPCAST:-$RELEASES/appcast.xml}
APP="$OUT/Leeway.app"
ZIP="$OUT/Leeway-$VERSION.zip"
TOOLS="$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/bin"
CREATE_DMG=${LEEWAY_CREATE_DMG:-1}
[[ $CREATE_DMG == 0 || $CREATE_DMG == 1 ]] || { printf 'LEEWAY_CREATE_DMG must be 0 or 1\n' >&2; exit 64; }
[[ ! -e "$OUT" ]] || { printf 'Output already exists: %s. Preserve it and use a new version or move the failed attempt.\n' "$OUT" >&2; exit 1; }
if [[ -f "$PREVIOUS" ]]; then
    python3 scripts/release_metadata.py history "$PREVIOUS" "$BUILD"
elif [[ -n ${LEEWAY_PREVIOUS_APPCAST:-} || $BUILD != 1 ]]; then
    printf 'A previous appcast is required after build 1. Set LEEWAY_PREVIOUS_APPCAST.\n' >&2
    exit 1
fi
for tool in xcodebuild swift lipo codesign spctl ditto xcrun hdiutil shasum git rsync; do
    command -v "$tool" >/dev/null
done
mkdir -p "$OUT/logs"
exec > >(tee "$OUT/logs/pipeline.log") 2>&1
trap 'printf "Release stopped at line %s. Logs: %s/logs\n" "$LINENO" "$OUT" >&2' ERR
printf '%s\n' "$NOTES" > "$OUT/release-notes.md"
printf '%s\n' "$SOURCE_COMMIT" > "$OUT/source-commit.txt"

notarize() {
    local artifact=$1 label=$2 submission
    xcrun notarytool submit "$artifact" --keychain-profile "$PROFILE" \
        --output-format json > "$OUT/logs/notary-$label-submit.json"
    submission=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$OUT/logs/notary-$label-submit.json")
    printf 'Waiting for notarization %s: %s\n' "$label" "$submission"
    xcrun notarytool wait "$submission" --keychain-profile "$PROFILE" \
        --timeout 30m --output-format json > "$OUT/logs/notary-$label.json"
    python3 - "$OUT/logs/notary-$label.json" <<'PY'
import json
import sys
from pathlib import Path
result = json.loads(Path(sys.argv[1]).read_text())
print("Notarization:", result.get("id"), result.get("status"))
if result.get("status") != "Accepted":
    sys.exit("Notarization was not accepted; inspect the submission log before retrying")
PY
}

verify_app() {
    local bundle=$1
    codesign --verify --deep --strict --verbose=2 "$bundle"
    spctl --assess --type execute --verbose=2 "$bundle"
    xcrun stapler validate "$bundle"
}

printf 'Building Leeway %s (build %s)\n' "$VERSION" "$BUILD"
xcodebuild -resolvePackageDependencies -project App/Leeway.xcodeproj -scheme Leeway \
    -derivedDataPath "$DERIVED" -onlyUsePackageVersionsFromResolvedFile < /dev/null > "$OUT/logs/resolve.log" 2>&1
[[ $("$TOOLS/generate_keys" --account "$ACCOUNT" -p) == \
    "$(sed -n 's/^LEEWAY_UPDATE_PUBLIC_KEY = //p' App/Version.xcconfig)" ]] || { printf 'Sparkle public key mismatch\n' >&2; exit 1; }
xcodebuild -project App/Leeway.xcodeproj -scheme Leeway -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
    -disableAutomaticPackageResolution 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO build < /dev/null > "$OUT/logs/app-build.log" 2>&1
ditto "$DERIVED/Build/Products/Release/Leeway.app" "$APP"
# SwiftPM binary frameworks must be embedded even when build-time signing is disabled.
if [[ ! -d "$APP/Contents/Frameworks/Sparkle.framework" ]]; then
    mkdir -p "$APP/Contents/Frameworks"
    ditto "$DERIVED/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
        "$APP/Contents/Frameworks/Sparkle.framework"
fi
for arch in arm64 x86_64; do
    printf 'Building CLI for %s\n' "$arch"
    swift build -c release --product leeway --triple "$arch-apple-macosx14.0" \
        --scratch-path "$ROOT/.build/cli-$arch" < /dev/null > "$OUT/logs/cli-$arch.log" 2>&1
done
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/share/leeway"
lipo -create "$ROOT/.build/cli-arm64/arm64-apple-macosx/release/leeway" \
    "$ROOT/.build/cli-x86_64/x86_64-apple-macosx/release/leeway" -output "$APP/Contents/Helpers/leeway"
# Ship the integration runtime with the CLI; omit caches and development artifacts.
rsync -a --exclude '__pycache__' --exclude '*.pyc' integrations/ "$APP/Contents/share/leeway/integrations/"
require_clean_worktree
[[ $(git rev-parse HEAD) == "$SOURCE_COMMIT" ]] || { printf 'Source commit changed during build.\n' >&2; exit 1; }
python3 scripts/sign_bundle.py "$APP" "$IDENTITY" App/Release.entitlements
codesign -d --verbose=4 "$APP" 2> "$OUT/logs/codesign-details.log"
python3 - "$APP/Contents/Info.plist" "$VERSION" "$BUILD" <<'PY'
import plistlib
import sys
with open(sys.argv[1], "rb") as stream:
    info = plistlib.load(stream)
if (info["CFBundleShortVersionString"], info["CFBundleVersion"]) != tuple(sys.argv[2:]):
    sys.exit("Built bundle version/build mismatch")
print("Bundle version:", info["CFBundleShortVersionString"], "build", info["CFBundleVersion"])
PY
printf 'Submitting app for notarization\n'
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/notarization.zip"
notarize "$OUT/notarization.zip" app
xcrun stapler staple "$APP"
verify_app "$APP" > "$OUT/logs/verify-app.log" 2>&1
cat "$OUT/logs/verify-app.log"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
# Verify exactly what users will extract, including the stapled ticket.
mkdir "$OUT/zip-check"
ditto -x -k "$ZIP" "$OUT/zip-check"
verify_app "$OUT/zip-check/Leeway.app" > "$OUT/logs/verify-zip.log" 2>&1
rm -r "$OUT/zip-check" "$OUT/notarization.zip"

SIGNATURE=$("$TOOLS/sign_update" --account "$ACCOUNT" -p "$ZIP")
printf '%s\n' "$SIGNATURE" > "$OUT/zip-signature.txt"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$ZIP" "$SIGNATURE"
cp "$OUT/release-notes.md" "$OUT/Leeway-$VERSION.md"
if [[ -f "$PREVIOUS" ]]; then cp "$PREVIOUS" "$OUT/appcast.xml"; fi
bash scripts/generate_appcast.sh "$VERSION" "$BUILD" "$TOOLS" "$OUT" > "$OUT/logs/appcast.log" 2>&1
python3 scripts/release_metadata.py feed "$OUT/appcast.xml" "$ZIP" "$VERSION" "$BUILD" "$SIGNATURE"
"$TOOLS/sign_update" --account "$ACCOUNT" "$OUT/appcast.xml"
"$TOOLS/sign_update" --account "$ACCOUNT" --verify "$OUT/appcast.xml"

ASSETS=("$ZIP" "$OUT/appcast.xml")
if [[ $CREATE_DMG == 1 ]]; then
    printf 'Creating DMG\n'
    mkdir "$OUT/dmg-stage"
    ditto "$APP" "$OUT/dmg-stage/Leeway.app"
    ln -s /Applications "$OUT/dmg-stage/Applications"
    DMG="$OUT/Leeway-$VERSION.dmg"
    hdiutil create -quiet -volname Leeway -srcfolder "$OUT/dmg-stage" -format UDZO "$DMG" < /dev/null
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    notarize "$DMG" dmg
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG" > "$OUT/logs/verify-dmg.log" 2>&1
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" >> "$OUT/logs/verify-dmg.log" 2>&1
    rm -r "$OUT/dmg-stage"
    ASSETS+=("$DMG")
fi
python3 scripts/write_cask.py "$VERSION" "$ZIP" "$OUT/leeway.rb"
CHECKSUM_FILES=("${ZIP##*/}" appcast.xml)
if [[ $CREATE_DMG == 1 ]]; then CHECKSUM_FILES+=("${DMG##*/}"); fi
(cd "$OUT" && shasum -a 256 "${CHECKSUM_FILES[@]}") > "$OUT/SHA256SUMS"
cp "$OUT/appcast.xml" "$RELEASES/appcast.xml"
ASSETS+=("$OUT/release-notes.md" "$OUT/SHA256SUMS")
COMMAND=(gh release create "v$VERSION" --repo "$REPO" --draft --title "Leeway $VERSION" \
    --target "$(cat "$OUT/source-commit.txt")" --notes-file "$OUT/release-notes.md")
if [[ $VERSION == *-* ]]; then COMMAND+=(--prerelease); fi
printf '%q ' "${COMMAND[@]}" "${ASSETS[@]}" > "$OUT/publish-draft.sh"
printf '\n' >> "$OUT/publish-draft.sh"
cp "$OUT/leeway.rb" Casks/leeway.rb
printf 'Local release ready. Review artifacts and the updated Casks/leeway.rb.\n'
printf 'Publication command (NOT executed):\n'
cat "$OUT/publish-draft.sh"
