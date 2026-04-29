#!/usr/bin/env bash
# Verifies statusline.js produces a complete 4-line output (exit 0) when git
# is absent from PATH. Skips silently when the host's "safe" PATH still
# happens to expose git.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

if ! command -v node >/dev/null 2>&1; then
    printf 'SKIP: node not available\n'
    exit 0
fi
NODE_BIN=$(command -v node)

# Minimal PATH that should not contain git on most systems.
SAFE_PATH="/usr/bin:/bin:/usr/sbin"

if PATH="$SAFE_PATH" command -v git >/dev/null 2>&1; then
    printf 'SKIP: git still on PATH (%s)\n' "$(PATH=$SAFE_PATH command -v git)"
    exit 0
fi

input='{"workspace":{"current_dir":"."}}'
out=$(printf '%s' "$input" | PATH="$SAFE_PATH" "$NODE_BIN" "$ROOT/statusline.js")
rc=$?

lines=$(printf '%s\n' "$out" | grep -c '.')

if [ $rc -ne 0 ]; then
    printf 'FAIL: exit code %d\n' "$rc" >&2
    printf '%s\n' "$out" >&2
    exit 1
fi
if [ "$lines" -lt 4 ]; then
    printf 'FAIL: only %d lines (expected 4)\n' "$lines" >&2
    printf '%s\n' "$out" >&2
    exit 1
fi
printf 'PASS: %d lines, exit 0\n' "$lines"
