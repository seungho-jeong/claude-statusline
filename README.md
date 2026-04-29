**English** | [한국어](README.ko.md)

# claude-code-statusline

> **Just glance.**  
> Your [Claude Code](https://www.anthropic.com/claude-code) limits, context, and active account — always in the same spot, no need to ask.

Instead of pausing work for `/usage`, `/context`, or `claude auth status`, just look.

## Preview

**Personal account**

![Personal account rendering](docs/images/personal.png)

**Team account (with warnings)**

![Team account rendering](docs/images/team.png)

## At a glance

- **`5h` limit**: usage bar, %, and time until reset. Highlights with `!` when under 15 minutes.
- **`Week` limit**: usage bar, %, and time until reset (shown in days/hours).
- **`✦` context**: model name, bar, %, token count. Color shifts at 50% and 80%, `!` above 90%. Abbreviates to `1.2M` past 1M tokens.
- **`@` account**: `@ Name` for personal, `@ Name (OrgName)` for team — so you never lose track when switching between accounts.
- **`$` cost**: cumulative for the session. Color shifts at $2 and $5, highlighted with `!` when exceeded.
- **cwd, `⎇` git, `❯` vim**: working directory, branch with dirty state (plus `⌥` worktree when applicable), vim mode.

## Install

`statusline.js` (Node ≥18) is the canonical runtime — cross-platform, zero npm
dependencies. The legacy `statusline.sh` is kept as a reference implementation
and will be phased out in a future release.

The installer creates timestamped backups (`*.bak.<YYYYMMDD-HHMMSS>`) of any
pre-existing `~/.claude/statusline.{sh,js}` and `~/.claude/settings.json`
before touching them — printed paths on completion.

### macOS / Linux / WSL2

```sh
curl -fsSL https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.sh | sh
```

### Windows (PowerShell 5.1+)

```powershell
iwr -useb https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.ps1 | iex
```

### Manual install

Place `statusline.js` at `~/.claude/statusline.js` (or
`%USERPROFILE%\.claude\statusline.js` on Windows) and add to
`~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "node ~/.claude/statusline.js",
    "padding": 0
  }
}
```

On Windows, the command becomes `node %USERPROFILE%\\.claude\\statusline.js`.
Windows Terminal + Git for Windows on Windows 10 1809+ is the supported
combination (ConPTY required for ANSI colors). Legacy `cmd.exe` runs without
crashing but ignores SGR escapes, so the output appears uncolored.

### Reference / legacy: shell runner

The original `statusline.sh` (bash + jq + coreutils) still ships in this repo
for byte-by-byte regression comparison against the Node port. It is supported
on macOS and Linux only and prints a deprecation warning on install:

```sh
curl -fsSL https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.sh | sh -s -- --runner sh
```

## Configuration

Every threshold can be overridden via `CCSL_*` environment variables.

| Variable | Default | Meaning |
|---|---|---|
| `CCSL_BAR_WIDTH` | `10` | Bar cell count |
| `CCSL_CTX_WARN` | `50` | Context % yellow threshold |
| `CCSL_CTX_CRIT` | `80` | Context % red threshold |
| `CCSL_FIRE_THRESHOLD` | `90` | Context `!` threshold |
| `CCSL_LIMIT_WARN_MIN` | `15` | 5h reset `!` threshold (minutes) |
| `CCSL_COST_WARN` | `2.0` | Cost yellow threshold ($) |
| `CCSL_COST_CRIT` | `5.0` | Cost red threshold ($) |
| `CCSL_GIT_TIMEOUT` | `1` | Git call upper bound (seconds) |

Example: `CCSL_CTX_WARN=30 claude`

## How it works

- **Account identity** is read directly from `oauthAccount` in `~/.claude.json`. No CLI call, so it stays stable across parallel sessions. Auto-generated organization names are filtered with a regex to distinguish personal and team accounts automatically.
- **Lightweight by design.** The Node runner uses `JSON.parse` and only forks `git`. The shell runner extracts every field with a single `jq` call using Unit Separator framing. Both share a per-CWD git cache file with a 5-second TTL.
- **Forgiving of missing data.** If `rate_limits`, `vim.mode`, `~/.claude.json`, or `jq` is absent, only that element is omitted — everything else still renders.

## Tests

```sh
./tests/run.sh                          # Snapshot diff (plain) for sh + js
./tests/run.sh --mode ansi              # Compare ANSI-preserved snapshots
./tests/run.sh --runner js              # Run js only
./tests/run.sh --update                 # Regenerate plain snapshots (from sh)
./tests/perf.sh                         # Cold-start gate: <80ms average
./tests/integration-no-git.sh           # Fallback when git is absent
./tests/integration-no-home.sh          # Fallback when HOME is unset / missing
./tests/integration-install-backup.sh   # install.sh backs up pre-existing assets
```

Tests run inside an isolated temp directory so your host's git / HOME / cache
state never leaks in.

## Dependencies

- **statusline.js (canonical)**: Node ≥18. Zero npm dependencies. `git` is optional — without it, line 2 falls back to `(no git repo)`.
- **statusline.sh (legacy)**: `jq`, `git`, plus macOS/Linux coreutils.
- **install.sh / install.ps1**: `curl` (or `Invoke-WebRequest` on Windows). `jq` optional — settings.json will simply not be auto-edited if absent.

## License

MIT. See [LICENSE](LICENSE).
