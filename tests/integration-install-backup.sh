#!/usr/bin/env bash
# Verifies install.sh creates timestamped backups before overwriting any
# pre-existing ~/.claude assets. Runs offline against a temporary HOME using
# --dry-run + --source so no network round-trip is required.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

TMPHOME=$(mktemp -d)
trap 'rm -rf "$TMPHOME"' EXIT

# Seed pre-existing assets that we expect the installer to back up.
mkdir -p "$TMPHOME/.claude"
printf '#!/bin/sh\n# old shell runner sentinel\n' > "$TMPHOME/.claude/statusline.sh"
chmod +x "$TMPHOME/.claude/statusline.sh"
printf '#!/usr/bin/env node\n// old js runner sentinel\n' > "$TMPHOME/.claude/statusline.js"
chmod +x "$TMPHOME/.claude/statusline.js"
printf '{"statusLine":{"type":"command","command":"old"}}\n' > "$TMPHOME/.claude/settings.json"

# Drive the installer in dry-run mode against the local source.
HOME="$TMPHOME" "$ROOT/install.sh" --dry-run --source "$ROOT/statusline.js" >/dev/null

# Each pre-existing file must have a *.bak.<ts> sibling.
fails=0
for name in statusline.sh statusline.js settings.json; do
    bak=$(ls "$TMPHOME/.claude/${name}".bak.* 2>/dev/null | head -n 1 || true)
    if [ -z "$bak" ]; then
        printf 'FAIL: no backup for %s\n' "$name" >&2
        fails=$((fails + 1))
        continue
    fi
    # Backup contents must match the seed; an in-place overwrite would have
    # corrupted them.
    if ! cmp -s "$TMPHOME/.claude/$name" "$bak"; then
        printf 'FAIL: backup for %s does not match original\n' "$name" >&2
        fails=$((fails + 1))
    fi
done

if [ "$fails" -ne 0 ]; then
    exit 1
fi
printf 'PASS: backups created for statusline.sh, statusline.js, settings.json\n'
