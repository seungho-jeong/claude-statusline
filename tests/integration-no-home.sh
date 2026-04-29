#!/usr/bin/env bash
# Verifies statusline.js does not crash when HOME points to a non-existent
# path. ~/.claude.json reads, cacheDir() lookups, and ~ expansion must all
# survive the missing directory.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
    printf 'SKIP: node not available\n'
    exit 0
fi

input='{"workspace":{"current_dir":"."}}'
out=$(printf '%s' "$input" \
    | HOME=/nonexistent USERPROFILE=/nonexistent \
      node "$ROOT/statusline.js" 2>&1)
rc=$?
lines=$(printf '%s\n' "$out" | grep -c '.')

if [ $rc -ne 0 ]; then
    printf 'FAIL: exit code %d\n' "$rc" >&2
    printf '%s\n' "$out" >&2
    exit 1
fi
if [ "$lines" -lt 1 ]; then
    printf 'FAIL: empty output\n' >&2
    exit 1
fi
printf 'PASS: %d lines, exit 0\n' "$lines"
