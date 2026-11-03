#!/bin/sh
set -eu
bundle=$1
/usr/bin/codesign --verify --deep --strict "$bundle"
/usr/bin/open -n -W "$bundle" --args --mock &
open_pid=$!
trap 'kill "$open_pid" 2>/dev/null || true' EXIT
sleep 4
if ! kill -0 "$open_pid" 2>/dev/null; then
    wait "$open_pid" || true
    printf '%s\n' 'FAIL: packaged app exited during launch'
    exit 1
fi
printf '%s\n' 'PASS: packaged app remains running after open'
