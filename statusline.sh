#!/usr/bin/env bash
# ============================================================================
# Claude Code Statusline — 4-line axis-separated layout
# ============================================================================
#
# Layout:
#   Line 1: Filesystem  — cwd (dim prefix + bold basename)
#   Line 2: Git         — ⌥ worktree(conditional) · ⎇ branch · ✓/± status
#   Line 3: AI          — ✦ model · context bar pct · used/max · @ tenancy(conditional)
#   Line 4: Resources   — $ cost · 5h bar pct (reset) · Week bar pct (reset) · ❯ vim mode
#
# Dependencies: jq, git, awk, date, tr
# ============================================================================

set -uo pipefail

# ----------------------------------
# Dependency check — graceful degrade if jq is missing
# ----------------------------------
if ! command -v jq >/dev/null 2>&1; then
    printf '▸ (jq not installed — statusline disabled)\n'
    exit 0
fi

# ----------------------------------
# Config — tweak thresholds here
# ----------------------------------
# Every constant below accepts a CCSL_<NAME> env override, e.g.
#   CCSL_CTX_WARN=30 CCSL_COST_CRIT=10.0 claude
BAR_WIDTH="${CCSL_BAR_WIDTH:-10}"
CTX_WARN="${CCSL_CTX_WARN:-50}"                  # % above which context turns yellow
CTX_CRIT="${CCSL_CTX_CRIT:-80}"                  # % above which context turns red
FIRE_THRESHOLD="${CCSL_FIRE_THRESHOLD:-90}"      # % above which ! appears on context
LIMIT_WARN_MIN="${CCSL_LIMIT_WARN_MIN:-15}"      # minutes below which ! appears on 5h timer
COST_WARN="${CCSL_COST_WARN:-2.0}"               # $ above which cost turns yellow
COST_CRIT="${CCSL_COST_CRIT:-5.0}"               # $ above which cost turns red (and icon -> !)
GIT_TIMEOUT="${CCSL_GIT_TIMEOUT:-1}"             # seconds — per git invocation upper bound (cold cache / slow FS)

# Timeout wrapper — macOS lacks `timeout` by default; fall back to `gtimeout`
# (coreutils) or bare git if neither is present. Exit 124 on timeout is
# absorbed by existing `2>/dev/null || true` patterns at call sites.
if   command -v timeout  >/dev/null 2>&1; then _TO=timeout
elif command -v gtimeout >/dev/null 2>&1; then _TO=gtimeout
else                                           _TO=""
fi
git_safe() {
    if [ -n "$_TO" ]; then "$_TO" "${GIT_TIMEOUT}s" git "$@"
    else                   git "$@"
    fi
}

# ----------------------------------
# ANSI colors
# ----------------------------------
RESET=$'\033[0m'
BOLD=$'\033[1m'
FG_CYAN=$'\033[38;5;80m'
FG_GREEN=$'\033[38;5;114m'
FG_YELLOW=$'\033[38;5;179m'
FG_RED=$'\033[38;5;203m'
FG_PINK=$'\033[38;5;218m'
FG_BLUE=$'\033[38;5;111m'
FG_LAVENDER=$'\033[38;5;147m'
FG_MUTED=$'\033[38;5;246m'
FG_SEP=$'\033[38;5;242m'
FG_DIM=$'\033[38;5;238m'

SEP="  ${FG_SEP}·${RESET}  "

# ----------------------------------
# Helpers
# ----------------------------------
make_bar() {
    local pct="$1"
    local width="${2:-$BAR_WIDTH}"
    (( pct < 0 )) && pct=0
    (( pct > 100 )) && pct=100
    local filled=$(( pct * width / 100 ))
    local empty=$(( width - filled ))
    local f=""
    local e=""
    if (( filled > 0 )); then printf -v f '%*s' "$filled" ''; f="${f// /▰}"; fi
    if (( empty  > 0 )); then printf -v e '%*s' "$empty"  ''; e="${e// /▱}"; fi
    printf '%s%s%s%s' "$f" "$FG_DIM" "$e" "$RESET"
}

color_by_pct() {
    local pct="$1"
    if   (( pct < CTX_WARN )); then printf '%s' "$FG_GREEN"
    elif (( pct < CTX_CRIT )); then printf '%s' "$FG_YELLOW"
    else                            printf '%s' "$FG_RED"
    fi
}

format_tokens() {
    local n="$1"
    if (( n >= 1000000 )); then
        # 1 decimal place via integer tenths (e.g. 1234567 → 12 tenths → 1.2M)
        local tenths=$(( n / 100000 ))
        printf '%d.%dM' "$(( tenths / 10 ))" "$(( tenths % 10 ))"
    elif (( n >= 1000 )); then
        # round to nearest k
        printf '%dk' "$(( (n + 500) / 1000 ))"
    else
        printf '%d' "$n"
    fi
}

# ----------------------------------
# Read JSON from stdin — bounded by 1s idle timeout (bash-native, no deps)
# Prevents indefinite block if CC spawns us without feeding stdin.
# ----------------------------------
INPUT=""
IFS= read -r -d '' -t 1 INPUT
[ -z "$INPUT" ] && INPUT='{}'

# Single jq call — extract all fields as Unit Separator (\x1f) joined record.
# \x1f is non-whitespace so bash `read` preserves empty fields between delimiters.
# Fallback record used if jq fails to parse (empty/malformed input).
jq_out=$(jq -r '[
    .model.display_name // "Claude",
    .workspace.current_dir // ".",
    ((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)),
    (.context_window.context_window_size // 200000),
    ((.context_window.used_percentage // (
        (((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)) * 100) /
        (.context_window.context_window_size // 200000)
    )) | floor),
    (.cost.total_cost_usd // 0),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.five_hour.used_percentage | if . == null then "" else floor end),
    (.rate_limits.seven_day.used_percentage | if . == null then "" else floor end),
    (.rate_limits.seven_day.resets_at // ""),
    (.vim.mode // "NORMAL"),
    (.workspace.git_worktree // "")
] | map(tostring) | join("\u001f")' <<<"$INPUT" 2>/dev/null) \
    || jq_out=$'Claude\x1f.\x1f0\x1f200000\x1f0\x1f0\x1f\x1f\x1f\x1f\x1fNORMAL\x1f'

IFS=$'\x1f' read -r \
    MODEL CWD CTX_USED CTX_MAX CTX_PCT COST \
    FIVE_RESET FIVE_PCT WEEK_PCT WEEK_RESET VIM_MODE WT_NAME <<<"$jq_out"

# ----------------------------------
# Line 1 — cwd (dim parent path + bold basename; "~" expansion)
# ----------------------------------
render_line1() {
    local p="$CWD"
    p="${p/#${HOME:-}/~}"

    # Single segment (e.g. "~", "/") — highlight whole string
    if [[ "$p" != */?* ]]; then
        printf '%s%s%s%s' "$FG_CYAN" "$BOLD" "$p" "$RESET"
        return
    fi

    local base="${p##*/}"
    local prefix="${p%/*}/"

    printf '%s%s%s%s%s%s' \
        "$FG_MUTED" "$prefix" "$RESET" \
        "$FG_CYAN$BOLD" "$base" "$RESET"
}

# ----------------------------------
# Line 2 — ⌥ worktree? · ⎇ branch · ✓/± status
# Cached 5s per CWD to avoid repeated git forks during heavy render cadence.
# ----------------------------------
_CACHE_DIR="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/claude-code-statusline-$UID"
_CACHE_TTL=5

_render_line2_compute() {
    if ! git_safe -C "$CWD" rev-parse --git-dir &>/dev/null; then
        printf '%s(no git repo)%s' "$FG_DIM" "$RESET"
        return
    fi

    local branch
    branch=$(git_safe -C "$CWD" branch --show-current 2>/dev/null || true)
    [ -z "$branch" ] && branch="detached"

    # Worktree — CC populates .workspace.git_worktree (WT_NAME) when cwd is
    # inside a linked worktree. Fall back to git-dir path matching for
    # stdin paths that predate this field.
    local wt_part=""
    if [ -n "$WT_NAME" ]; then
        wt_part="⌥ ${FG_LAVENDER}wt:${WT_NAME}${RESET}${SEP}"
    else
        local git_dir
        git_dir=$(git_safe -C "$CWD" rev-parse --git-dir 2>/dev/null)
        if [[ "$git_dir" == *"/.git/worktrees/"* ]]; then
            local wt_root wt_fallback
            wt_root=$(git_safe -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
            wt_fallback="${wt_root##*/}"
            wt_part="⌥ ${FG_LAVENDER}wt:${wt_fallback}${RESET}${SEP}"
        fi
    fi

    # Dirty status
    local status_part
    local porcelain
    porcelain=$(git_safe -C "$CWD" status --porcelain 2>/dev/null)
    if [ -z "$porcelain" ]; then
        status_part="✓ ${FG_GREEN}clean${RESET}"
    else
        local files added=0 deleted=0
        local _nl="${porcelain//[!$'\n']/}"
        files=$(( ${#_nl} + 1 ))
        local shortstat
        shortstat=$(git_safe -C "$CWD" diff --shortstat HEAD 2>/dev/null || echo "")
        [[ "$shortstat" =~ ([0-9]+)[[:space:]]+insertion ]] && added="${BASH_REMATCH[1]}"
        [[ "$shortstat" =~ ([0-9]+)[[:space:]]+deletion  ]] && deleted="${BASH_REMATCH[1]}"
        status_part="± ${FG_RED}${files} files${RESET} ${FG_SEP}·${RESET} ${FG_GREEN}+${added}${RESET} ${FG_RED}−${deleted}${RESET}"
    fi

    printf '%s⎇ %s%s%s%s%s' \
        "$wt_part" "$FG_YELLOW" "$branch" "$RESET" "$SEP" "$status_part"
}

render_line2() {
    # Cache key: sanitized CWD (no fork, no hash tool dependency)
    local key="${CWD//[^a-zA-Z0-9_-]/_}"
    local cache_file="${_CACHE_DIR}/git-${key}.cache"

    # Cache hit: file exists and age < TTL
    if [ -f "$cache_file" ]; then
        local mtime now
        mtime=$(stat -f %m "$cache_file" 2>/dev/null || stat -c %Y "$cache_file" 2>/dev/null || echo 0)
        now=$(date +%s)
        if (( now - mtime < _CACHE_TTL )); then
            cat "$cache_file"
            return
        fi
    fi

    # Miss: compute, emit, then cache (best-effort atomic write)
    local out
    out=$(_render_line2_compute)
    printf '%s' "$out"

    mkdir -p "$_CACHE_DIR" 2>/dev/null && chmod 700 "$_CACHE_DIR" 2>/dev/null
    if printf '%s' "$out" > "${cache_file}.tmp.$$" 2>/dev/null; then
        mv "${cache_file}.tmp.$$" "$cache_file" 2>/dev/null || rm -f "${cache_file}.tmp.$$" 2>/dev/null
    fi
}

# ----------------------------------
# Tenancy — identity (+ team org when applicable) from ~/.claude.json
# ----------------------------------
read_tenancy() {
    local f="${HOME:-~}/.claude.json"
    [ -f "$f" ] || return 1
    local fields
    fields=$(jq -r '[
        .oauthAccount.organizationName // "",
        .oauthAccount.displayName // "",
        .oauthAccount.emailAddress // ""
    ] | @tsv' "$f" 2>/dev/null) || return 1
    IFS=$'\t' read -r ORG_NAME DISPLAY_NAME EMAIL <<<"$fields"
    [ -n "$DISPLAY_NAME" ] || [ -n "$EMAIL" ]
}

format_tenancy() {
    local name="${DISPLAY_NAME:-${EMAIL%@*}}"
    [ -z "$name" ] && return 1

    # Personal: orgName is empty or matches auto-generated pattern
    # Team: orgName is a custom team name
    if [ -z "$ORG_NAME" ] || [[ "$ORG_NAME" =~ \'s\ (Individual\ )?Organization$ ]]; then
        printf '@ %s%s%s' "$FG_LAVENDER" "$name" "$RESET"
    else
        printf '@ %s%s%s %s(%s%s%s%s%s)%s' \
            "$FG_LAVENDER" "$name" "$RESET" \
            "$FG_SEP" "$RESET" \
            "$FG_BLUE" "$ORG_NAME" "$RESET" \
            "$FG_SEP" "$RESET"
    fi
}

# ----------------------------------
# Line 3 — ✦ model · context bar + pct · used/max · @ tenancy(conditional)
# ----------------------------------
render_line3() {
    local color bar used_fmt max_fmt extra=""
    color=$(color_by_pct "$CTX_PCT")
    bar=$(make_bar "$CTX_PCT")
    used_fmt=$(format_tokens "$CTX_USED")
    max_fmt=$(format_tokens "$CTX_MAX")
    (( CTX_PCT >= FIRE_THRESHOLD )) && extra=" !"

    local suffix="" t
    if read_tenancy && t=$(format_tenancy); then
        suffix="${SEP}${t}"
    fi

    printf '✦ %s%s%s%s%s  %s%s%3d%%%s%s %s·%s %s%s / %s%s%s' \
        "$FG_PINK" "$MODEL" "$RESET" "$SEP" \
        "$bar" \
        "$color" "$BOLD" "$CTX_PCT" "$RESET" "$extra" \
        "$FG_SEP" "$RESET" \
        "$FG_MUTED" "$used_fmt" "$max_fmt" "$RESET" \
        "$suffix"
}

# ----------------------------------
# Line 4 — $ cost · 5h bar+pct (reset) · Week bar+pct (reset) · ❯ vim mode
# ----------------------------------
_to_cents() {
    # Convert "$1" (float-ish string like "1.34", "5", "0.5") to integer cents
    # and store in var named "$2". No subshells.
    local v="$1" out_var="$2"
    if [[ "$v" == *.* ]]; then
        local i="${v%%.*}" f="${v#*.}00"
        printf -v "$out_var" '%d' "$(( 10#${i:-0} * 100 + 10#${f:0:2} ))"
    else
        printf -v "$out_var" '%d' "$(( 10#${v:-0} * 100 ))"
    fi
}

format_cost() {
    local cost="$1"
    local _ci _cw _cc
    _to_cents "$cost"       _ci
    _to_cents "$COST_WARN"  _cw
    _to_cents "$COST_CRIT"  _cc
    local color extra=""
    if   (( _ci < _cw )); then color="$FG_GREEN"
    elif (( _ci < _cc )); then color="$FG_YELLOW"
    else                       color="$FG_RED"; extra=" !"
    fi
    printf '$ %s%s%.2f%s%s' "$color" "$BOLD" "$cost" "$RESET" "$extra"
}

format_remaining() {
    local reset_epoch="$1"
    [ -z "$reset_epoch" ] && { printf -- '--'; return; }
    [[ "$reset_epoch" =~ ^[0-9]+$ ]] || { printf -- '--'; return; }

    local now diff
    now=$(date +%s)
    diff=$(( reset_epoch - now ))
    if   (( diff <= 0     )); then printf 'reset'
    elif (( diff >= 86400 )); then printf '%dd %dh' $(( diff/86400 )) $(( (diff%86400)/3600 ))
    elif (( diff >= 3600  )); then printf '%dh %dm' $(( diff/3600 )) $(( (diff%3600)/60 ))
    else                           printf '%dm' $(( diff/60 ))
    fi
}

render_line4() {
    # Cost
    local cost_part
    cost_part=$(format_cost "$COST")

    # 5h block
    local five_color five_bar five_pct_str five_remain_str five_extra=""
    five_remain_str=$(format_remaining "$FIVE_RESET")
    if [ -n "$FIVE_PCT" ]; then
        five_color=$(color_by_pct "$FIVE_PCT")
        five_bar=$(make_bar "$FIVE_PCT")
        five_pct_str=$(printf '%3d%%' "$FIVE_PCT")
    else
        five_color="$FG_MUTED"
        five_bar=$(make_bar 0)
        five_pct_str=' --%'
    fi

    # ! warning when few minutes remain
    if [[ "$five_remain_str" =~ ^([0-9]+)m$ ]] && (( ${BASH_REMATCH[1]} <= LIMIT_WARN_MIN )); then
        five_extra=" !"
    fi

    # Reset time in parens, suppressed when absent
    local five_remain_seg=""
    if [ "$five_remain_str" != "--" ]; then
        five_remain_seg=$(printf ' %s(%s%s%s%s%s)%s' \
            "$FG_SEP" "$FG_MUTED" "$five_remain_str" "$five_extra" "$RESET" "$FG_SEP" "$RESET")
    fi

    # Weekly
    local week_color week_bar week_pct_str week_remain_str week_remain_seg=""
    week_remain_str=$(format_remaining "$WEEK_RESET")
    if [ -n "$WEEK_PCT" ]; then
        week_color=$(color_by_pct "$WEEK_PCT")
        week_bar=$(make_bar "$WEEK_PCT")
        week_pct_str=$(printf '%3d%%' "$WEEK_PCT")
    else
        week_color="$FG_MUTED"
        week_bar=$(make_bar 0)
        week_pct_str=' --%'
    fi

    if [ "$week_remain_str" != "--" ]; then
        week_remain_seg=$(printf ' %s(%s%s%s%s)%s' \
            "$FG_SEP" "$FG_MUTED" "$week_remain_str" "$RESET" "$FG_SEP" "$RESET")
    fi

    printf '%s%s5h %s  %s%s%s%s%sWeek %s  %s%s%s%s%s❯  %s%s%s' \
        "$cost_part" "$SEP" \
        "$five_bar" "$five_color" "$five_pct_str" "$RESET" "$five_remain_seg" "$SEP" \
        "$week_bar" "$week_color" "$week_pct_str" "$RESET" "$week_remain_seg" "$SEP" \
        "$FG_MUTED" "$VIM_MODE" "$RESET"
}

# ----------------------------------
# Output
# ----------------------------------
render_line1; printf '\n'
render_line2; printf '\n'
render_line3; printf '\n'
render_line4; printf '\n'
