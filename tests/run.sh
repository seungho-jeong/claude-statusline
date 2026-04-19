#!/usr/bin/env bash
# Pure-bash snapshot runner. Compares ANSI-stripped statusline output
# against tests/expected/<name>.txt. Missing expected files are created
# (first-run snapshot). Exits non-zero on any diff.
#
# Usage:  ./tests/run.sh            # run all fixtures
#         ./tests/run.sh --update   # regenerate all expected snapshots
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

TMPHOME=$(mktemp -d)
NOGIT=$(mktemp -d)
CACHE=$(mktemp -d)
trap 'rm -rf "$TMPHOME" "$NOGIT" "$CACHE"' EXIT

pass=0
fail=0
for fx in tests/fixtures/*.json; do
    name=$(basename "$fx" .json)
    expected="tests/expected/${name}.txt"

    input=$(sed "s|__NOGIT__|${NOGIT}|g" "$fx")
    # Execute from NOGIT so fixtures without explicit CWD ('.') resolve
    # to a non-git dir — removing host repo state from the snapshot.
    actual=$(cd "$NOGIT" && printf '%s\0' "$input" \
        | HOME="$TMPHOME" XDG_RUNTIME_DIR="$CACHE" TMPDIR="$CACHE" \
          "$ROOT/statusline.sh" \
        | sed $'s/\x1b\\[[0-9;]*m//g' \
        | sed "s|${NOGIT}|__NOGIT__|g")

    if [ $UPDATE -eq 1 ] || [ ! -f "$expected" ]; then
        printf '%s' "$actual" > "$expected"
        printf 'SNAP %s\n' "$name"
        pass=$((pass + 1))
        continue
    fi

    if [ "$actual" = "$(cat "$expected")" ]; then
        printf 'PASS %s\n' "$name"
        pass=$((pass + 1))
    else
        printf 'FAIL %s\n' "$name"
        diff <(cat "$expected") <(printf '%s' "$actual") || true
        fail=$((fail + 1))
    fi
done

printf '\n%d pass, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
