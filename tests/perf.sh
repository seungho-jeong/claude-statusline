#!/usr/bin/env bash
# Cold-start perf gate. Spawns `node statusline.js` 5 times after a warm-up
# and compares the average wall time against $CCSL_PERF_THRESHOLD_MS (default
# 80ms). Each iteration is measured outside the runner using process.hrtime
# so process startup is included.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

THRESHOLD_MS="${CCSL_PERF_THRESHOLD_MS:-80}"
FX="$ROOT/tests/fixtures/01-default.json"

if ! command -v node >/dev/null 2>&1; then
    printf 'SKIP: node not available\n'
    exit 0
fi

# Warm filesystem cache.
node "$ROOT/statusline.js" < "$FX" >/dev/null

avg=$(node - "$ROOT/statusline.js" "$FX" <<'NODE'
const { spawnSync } = require('child_process');
const fs = require('fs');
const [, , script, fx] = process.argv;
const buf = fs.readFileSync(fx);

const samples = [];
for (let i = 0; i < 5; i++) {
    const t0 = process.hrtime.bigint();
    spawnSync(process.execPath, [script], {
        input: buf,
        stdio: ['pipe', 'ignore', 'ignore'],
    });
    const t1 = process.hrtime.bigint();
    samples.push(Number(t1 - t0) / 1e6);
}
const avg = samples.reduce((a, b) => a + b, 0) / samples.length;
process.stderr.write(`samples (ms): ${samples.map(s => s.toFixed(2)).join(', ')}\n`);
process.stdout.write(avg.toFixed(2));
NODE
)

printf 'average: %s ms (threshold: %s ms)\n' "$avg" "$THRESHOLD_MS"

# Compare with awk (portable; bash arithmetic is integer-only).
if awk -v a="$avg" -v t="$THRESHOLD_MS" 'BEGIN { exit (a < t) ? 0 : 1 }'; then
    printf 'PASS\n'
else
    printf 'FAIL: average %s ms exceeds threshold %s ms\n' "$avg" "$THRESHOLD_MS" >&2
    exit 1
fi
