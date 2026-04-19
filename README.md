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

```sh
curl -fsSL https://raw.githubusercontent.com/seungho-jeong/claude-code-statusline/main/install.sh | sh
```

Manual install: place `statusline.sh` at `~/.claude/statusline.sh` and add the following to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "padding": 0
  }
}
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
- **Lightweight by design.** A single `jq` call extracts every field at once using Unit Separator framing, and git info is reused from a per-CWD file cache with a 5-second TTL.
- **Forgiving of missing data.** If `rate_limits`, `vim.mode`, `~/.claude.json`, or `jq` is absent, only that element is omitted — everything else still renders.

## Tests

```sh
./tests/run.sh              # Snapshot diff after ANSI strip
./tests/run.sh --update     # Regenerate after an intentional format change
```

Runs in an isolated temp directory so your host's git/HOME/cache state never leaks in.

## Dependencies

`jq`, `git`, `curl`, plus standard macOS/Linux coreutils.

## License

MIT. See [LICENSE](LICENSE).
