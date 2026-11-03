#!/bin/bash
# Keep stable releases on Sparkle's default channel, including with Bash 3.2.
set -euo pipefail
VERSION=$1
BUILD=$2
TOOLS=$3
OUT=$4
ARGS=(--account leeway --versions "$BUILD" --maximum-versions 0 --maximum-deltas 0 \
    --embed-release-notes --download-url-prefix \
    "https://github.com/YarinCardillo/leeway/releases/download/v$VERSION/")
if [[ $VERSION == *-* ]]; then ARGS+=(--channel beta); fi
"$TOOLS/generate_appcast" "${ARGS[@]}" "$OUT"
