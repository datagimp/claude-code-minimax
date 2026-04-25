# model-switcher

Two small scripts for using **MiniMax** as a backend for [Claude Code](https://claude.ai/code) on Windows:

- **`switch.ps1`** — toggle Claude Code between Anthropic (default OAuth) and MiniMax with one command.
- **`statusline-usage.sh`** — a status bar that shows your current 5-hour MiniMax Token Plan usage (or your Anthropic Pro/Max rate limits, depending on which provider is active).

## Why

Claude Code can talk to any Anthropic-compatible endpoint via the `ANTHROPIC_BASE_URL` and `ANTHROPIC_API_KEY` env vars. MiniMax exposes an Anthropic-compatible endpoint at `https://api.minimax.io/anthropic`, so flipping those two variables is enough to switch providers — `switch.ps1` automates the flip and persists it to your PowerShell `$PROFILE` so it survives new windows.

The status bar adapts to whichever provider is active: in MiniMax mode it pulls live quota from MiniMax's `/v1/token_plan/remains` endpoint and shows a `MM` prefix; in Anthropic mode it falls through to the default behavior (5h / 7d rate limits provided by Claude Code itself).

## Setup

### 1. Add your MiniMax API key

Either set an environment variable, or drop the key in a file:

```powershell
# Option A (env var)
$env:MINIMAX_API_KEY = "sk-cp-..."

# Option B (file — gitignored)
cp .minimax-key.example .minimax-key
# then edit .minimax-key and paste your key on the first line
```

Get a key from <https://platform.minimax.io>.

### 2. Install the toggle

Run `switch.ps1` whenever you want to flip providers:

```powershell
. .\switch.ps1
```

Each invocation toggles between Anthropic ↔ MiniMax. The change applies to the current session and all future PowerShell windows. **Restart Claude Code** for it to pick up the new env vars.

### 3. Install the status bar (optional)

```bash
# from a Git Bash / WSL shell
cp statusline-usage.sh ~/.claude/statusline-usage.sh
chmod +x ~/.claude/statusline-usage.sh
```

Then in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-usage.sh"
  }
}
```

Restart Claude Code. In MiniMax mode you'll see something like:

```
MM 5h: ███░░░░░ 39% reset 33m  |  ctx: ███░░░░░ 42%
```

## Files

| File | Purpose | Tracked |
|---|---|---|
| `switch.ps1` | Toggle script | yes |
| `statusline-usage.sh` | Status bar | yes |
| `.minimax-key.example` | Template for your local key file | yes |
| `.gitignore` | Excludes `.minimax-key` and Claude Code local settings | yes |
| `.minimax-key` | Your real API key | no (gitignored) |

## Credits

The status bar is derived from [`bhutano/claude-usage-bar`](https://github.com/bhutano/claude-usage-bar) (MIT-licensed) by [@bhutano](https://github.com/bhutano). It was extended here to read MiniMax's `/v1/token_plan/remains` endpoint when in MiniMax mode; all original Anthropic-mode behavior is preserved unchanged. The unchanged upstream version is also mirrored at [`datagimp/claude-usage-bar`](https://github.com/datagimp/claude-usage-bar).
