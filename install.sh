#!/bin/sh
set -eu

# Usage:
#   install.sh                       # install statusline.js (Node, default)
#   install.sh --runner sh           # install statusline.sh (legacy, deprecated)
#   install.sh --source <path>       # install from a local file instead of curl
#   install.sh --dry-run             # backup + plan only; no download or settings edit
#
# Pre-existing files in $HOME/.claude (statusline.{sh,js}, settings.json) are
# backed up to *.bak.<YYYYMMDD-HHMMSS> before any change. Backup paths are
# printed on exit. Set HOME to redirect installation to an alternate prefix.

RUNNER="js"
SOURCE=""
DRY_RUN=0
while [ $# -gt 0 ]; do
    case "$1" in
        --runner)
            shift
            case "${1:-}" in
                sh|js) RUNNER="$1" ;;
                *) printf 'error: --runner expects sh or js\n' >&2; exit 2 ;;
            esac
            ;;
        --source)
            shift
            SOURCE="${1:-}"
            [ -z "$SOURCE" ] && { printf 'error: --source expects a path\n' >&2; exit 2; }
            ;;
        --dry-run) DRY_RUN=1 ;;
        *) printf 'error: unknown argument: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

if [ "$RUNNER" = "sh" ]; then
    cat >&2 <<'WARN'
warning: --runner sh is deprecated. The shell runner depends on jq and
coreutils which break on Alpine, BusyBox, and Windows. The Node runner
(default) is now the canonical implementation. See the README "Migration"
section for the staged removal timeline.
WARN
fi

REPO_RAW="https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main"
CLAUDE_DIR="$HOME/.claude"
SETTINGS="$CLAUDE_DIR/settings.json"

if [ "$RUNNER" = "js" ]; then
    DEST="$CLAUDE_DIR/statusline.js"
    SRC="statusline.js"
    CMD="node $CLAUDE_DIR/statusline.js"
    REQUIRED="curl node"
else
    DEST="$CLAUDE_DIR/statusline.sh"
    SRC="statusline.sh"
    CMD="$CLAUDE_DIR/statusline.sh"
    REQUIRED="jq curl"
fi

# Node version gate (js mode only, when node is on PATH).
if [ "$RUNNER" = "js" ] && command -v node >/dev/null 2>&1; then
    NODE_MAJOR=$(node -e 'process.stdout.write(String(process.versions.node.split(".")[0]))' 2>/dev/null || echo 0)
    if [ "$NODE_MAJOR" -lt 18 ]; then
        printf 'error: node v18+ required (found v%s). install a newer node.\n' "$NODE_MAJOR" >&2
        exit 1
    fi
fi

# Required-binary check. curl is skipped in --dry-run (no download happens).
for cmd in $REQUIRED; do
    if [ "$DRY_RUN" -eq 1 ] && [ "$cmd" = "curl" ]; then continue; fi
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'error: %s not found. install it first.\n' "$cmd" >&2
        exit 1
    }
done

mkdir -p "$CLAUDE_DIR"
chmod 700 "$CLAUDE_DIR" 2>/dev/null || true

# Timestamped backup of any pre-existing assets. Bail on first failure.
TS=$(date +%Y%m%d-%H%M%S)
BACKUPS=""
for f in "$CLAUDE_DIR/statusline.sh" "$CLAUDE_DIR/statusline.js" "$SETTINGS"; do
    if [ -f "$f" ]; then
        bak="${f}.bak.${TS}"
        cp -p "$f" "$bak" || {
            printf 'error: backup failed for %s\n' "$f" >&2
            exit 1
        }
        BACKUPS="${BACKUPS}  ${bak}\n"
    fi
done

if [ "$DRY_RUN" -eq 1 ]; then
    printf 'dry-run: backups created (no download or settings edit).\n'
    [ -n "$BACKUPS" ] && printf 'backups:\n%b' "$BACKUPS"
    exit 0
fi

# Atomic download: write to tmp, then mv onto destination.
tmp=$(mktemp)
if [ -n "$SOURCE" ]; then
    cp -p "$SOURCE" "$tmp"
else
    curl -fsSL "$REPO_RAW/$SRC" -o "$tmp"
fi
chmod +x "$tmp" 2>/dev/null || true
mv "$tmp" "$DEST"

# Update settings.json. jq does an in-place edit via tmp+mv; without jq the
# user is prompted to add the entry by hand.
if [ -f "$SETTINGS" ]; then
    if command -v jq >/dev/null 2>&1; then
        tmp=$(mktemp)
        jq --arg cmd "$CMD" '.statusLine = {"type":"command","command":$cmd,"padding":0}' \
            "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    else
        printf 'warning: jq not installed; settings.json was not updated.\n' >&2
        printf 'add this manually:\n  "statusLine": {"type":"command","command":"%s","padding":0}\n' "$CMD" >&2
    fi
else
    printf '{"statusLine":{"type":"command","command":"%s","padding":0}}\n' "$CMD" > "$SETTINGS"
fi

printf 'installed (%s). restart Claude Code to apply.\n' "$RUNNER"
if [ -n "$BACKUPS" ]; then
    printf 'backups:\n%b' "$BACKUPS"
fi
