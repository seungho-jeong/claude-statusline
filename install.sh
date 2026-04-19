#!/usr/bin/env bash
set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main"
DEST="$HOME/.claude/statusline.sh"
SETTINGS="$HOME/.claude/settings.json"

for cmd in jq git curl; do
    command -v "$cmd" >/dev/null 2>&1 || {
        printf 'error: %s not found. install it first.\n' "$cmd" >&2
        exit 1
    }
done

mkdir -p "$(dirname "$DEST")"
curl -fsSL "$REPO_RAW/statusline.sh" -o "$DEST"
chmod +x "$DEST"

if [ -f "$SETTINGS" ]; then
    tmp=$(mktemp)
    jq '.statusLine = {"type":"command","command":"~/.claude/statusline.sh","padding":0}' \
        "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
else
    mkdir -p "$(dirname "$SETTINGS")"
    printf '{"statusLine":{"type":"command","command":"~/.claude/statusline.sh","padding":0}}\n' > "$SETTINGS"
fi

printf 'installed. restart Claude Code to apply.\n'
