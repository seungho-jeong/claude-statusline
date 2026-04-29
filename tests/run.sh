#!/usr/bin/env bash
# Pure-bash snapshot runner. Compares statusline output against
# tests/expected/<name>.txt (plain mode, ANSI-stripped) or
# tests/expected-ansi/<name>.txt (ansi mode, ANSI preserved).
# Missing expected files are created (first-run snapshot).
# Exits non-zero on any diff.
#
# Runs both runners by default so the sh/js pair stays in lock-step; a runner
# can be selected explicitly via --runner.
#
# Usage:  ./tests/run.sh                       # plain mode against sh + js
#         ./tests/run.sh --mode ansi           # compare ANSI-preserved snapshots
#         ./tests/run.sh --update              # regenerate plain snapshots (sh)
#         ./tests/run.sh --mode ansi --update  # regenerate ansi snapshots (sh)
#         ./tests/run.sh --runner sh           # run sh only
#         ./tests/run.sh --runner js           # run js only
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

UPDATE=0
RUNNERS="sh js"
MODE=plain
while [ $# -gt 0 ]; do
    case "$1" in
        --update) UPDATE=1 ;;
        --runner)
            shift
            case "${1:-}" in
                sh|js) RUNNERS="$1" ;;
                *) printf 'error: --runner expects sh or js\n' >&2; exit 2 ;;
            esac
            ;;
        --mode)
            shift
            case "${1:-}" in
                plain|ansi) MODE="$1" ;;
                *) printf 'error: --mode expects plain or ansi\n' >&2; exit 2 ;;
            esac
            ;;
        *) printf 'error: unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

# Updates always regenerate from sh (the reference implementation).
if [ $UPDATE -eq 1 ]; then RUNNERS="sh"; fi

case "$MODE" in
    plain) EXPECTED_DIR="tests/expected" ;;
    ansi)  EXPECTED_DIR="tests/expected-ansi" ;;
esac
mkdir -p "$EXPECTED_DIR"

# Silent skip when a runner's prerequisites are unavailable.
runner_available() {
    case "$1" in
        sh) [ -x "$ROOT/statusline.sh" ] ;;
        js) command -v node >/dev/null 2>&1 && [ -f "$ROOT/statusline.js" ] ;;
    esac
}

runner_cmd() {
    case "$1" in
        sh) printf '%s' "$ROOT/statusline.sh" ;;
        js) printf 'node %s' "$ROOT/statusline.js" ;;
    esac
}

maybe_strip_ansi() {
    if [ "$MODE" = "plain" ]; then
        sed $'s/\x1b\\[[0-9;]*m//g'
    else
        cat
    fi
}

TMPHOME=$(mktemp -d)
NOGIT=$(mktemp -d)
NOGIT_PARENT="$(dirname "$NOGIT")"
NOGIT_BASE="$(basename "$NOGIT")"
CACHE=$(mktemp -d)
trap 'rm -rf "$TMPHOME" "$NOGIT" "$CACHE"' EXIT

pass=0
fail=0
for runner in $RUNNERS; do
    if ! runner_available "$runner"; then
        printf 'SKIP runner=%s (prerequisite missing)\n' "$runner"
        continue
    fi
    cmd=$(runner_cmd "$runner")

    for fx in tests/fixtures/*.json; do
        name=$(basename "$fx" .json)
        expected="${EXPECTED_DIR}/${name}.txt"

        input=$(sed "s|__NOGIT__|${NOGIT}|g" "$fx")
        # Execute from NOGIT so fixtures without explicit CWD ('.') resolve
        # to a non-git dir — removing host repo state from the snapshot.
        # Fresh CACHE per runner to avoid cross-runner cache reuse of Line 2.
        rcache=$(mktemp -d)
        # NOGIT path normalization: in plain mode the full path stays
        # contiguous after ANSI stripping, so the first sed wins. In ansi
        # mode the dim prefix and bold basename are separated by SGR escapes,
        # so we fall back to per-segment substitution.
        actual=$(cd "$NOGIT" && printf '%s\0' "$input" \
            | HOME="$TMPHOME" XDG_RUNTIME_DIR="$rcache" TMPDIR="$rcache" \
              $cmd \
            | maybe_strip_ansi \
            | sed -e "s|${NOGIT}|__NOGIT__|g" \
                  -e "s|${NOGIT_PARENT}|__NOGIT_PARENT__|g" \
                  -e "s|${NOGIT_BASE}|__NOGIT_BASE__|g")
        rm -rf "$rcache"

        if [ $UPDATE -eq 1 ] || [ ! -f "$expected" ]; then
            printf '%s' "$actual" > "$expected"
            printf 'SNAP [%s] %s\n' "$runner" "$name"
            pass=$((pass + 1))
            continue
        fi

        if [ "$actual" = "$(cat "$expected")" ]; then
            printf 'PASS [%s] %s\n' "$runner" "$name"
            pass=$((pass + 1))
        else
            printf 'FAIL [%s] %s\n' "$runner" "$name"
            diff <(cat "$expected") <(printf '%s' "$actual") || true
            fail=$((fail + 1))
        fi
    done
done

printf '\n%d pass, %d fail\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
