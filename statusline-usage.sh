#!/bin/bash
# ──────────────────────────────────────────────────────────────
#  claude-usage-bar  —  status line for Claude Code CLI
#
#  Original: https://github.com/bhutano/claude-usage-bar
#    Copyright (c) 2026 bhutano — MIT License
#  MiniMax extensions: https://github.com/datagimp/claude-code-minimax
#    Copyright (c) 2026 datagimp — MIT License
#  See LICENSE for full terms.
#
#  Requirements: Python 3  (auto-detected)
#  Works on: macOS, Linux, Windows (Git Bash / WSL)
#
#  Language: set USAGE_BAR_LANG=en|it in ~/.claude/usage-bar.conf
#  or as an environment variable. Defaults to "en".
# ──────────────────────────────────────────────────────────────

INPUT=$(cat)

# ── Read language config ──────────────────────────────────────
LANG_CODE="${USAGE_BAR_LANG:-}"
CONFIG_FILE="$HOME/.claude/usage-bar.conf"
if [ -z "$LANG_CODE" ] && [ -f "$CONFIG_FILE" ]; then
    LANG_CODE=$(grep '^LANG=' "$CONFIG_FILE" 2>/dev/null | head -1 | cut -d= -f2 | tr -d '[:space:]')
fi
LANG_CODE="${LANG_CODE:-en}"

# ── Auto-detect Python 3 ──────────────────────────────────────
PYTHON=""
for candidate in python3 python /c/Python313/python /usr/bin/python3 /usr/local/bin/python3; do
    if "$candidate" -c "import sys; assert sys.version_info >= (3,6)" 2>/dev/null; then
        PYTHON="$candidate"
        break
    fi
done

if [ -z "$PYTHON" ]; then
    echo "[ claude-usage-bar: Python 3 not found / Python 3 non trovato ]"
    exit 0
fi

"$PYTHON" - <<'PYEOF' "$INPUT" "$LANG_CODE"
# -*- coding: utf-8 -*-
import sys, json, datetime, io, os, time, tempfile

# Force UTF-8 on Windows (avoids cp1252 encoding errors)
if sys.platform == "win32":
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

data_str = sys.argv[1] if len(sys.argv) > 1 else ""
lang     = sys.argv[2] if len(sys.argv) > 2 else "en"

# ── MiniMax mode detection & data fetch ───────────────────────
MM_PREFIX     = ""
MM_TEXT_MODEL = "MiniMax-M*"
MM_CACHE      = os.path.expanduser("~/.claude/usage-bar.minimax-cache.json")
MM_TTL        = 60   # seconds
MM_TIMEOUT    = 3    # seconds for the API call

def _mm_load_cache():
    try:
        with open(MM_CACHE, "r", encoding="utf-8") as f:
            return json.load(f), os.path.getmtime(MM_CACHE)
    except Exception:
        return None, 0

def _mm_save_cache(payload):
    try:
        d = os.path.dirname(MM_CACHE) or "."
        fd, tmp = tempfile.mkstemp(prefix=".usage-bar-mm-", dir=d)
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f)
        os.replace(tmp, MM_CACHE)
    except Exception:
        pass

def _mm_fetch(api_key):
    import urllib.request, urllib.error
    req = urllib.request.Request(
        "https://www.minimax.io/v1/token_plan/remains",
        headers={
            "Authorization": "Bearer " + api_key,
            "Content-Type": "application/json",
            "User-Agent": "claude-usage-bar/1.0",
        },
    )
    with urllib.request.urlopen(req, timeout=MM_TIMEOUT) as resp:
        return json.loads(resp.read().decode("utf-8"))

def _mm_pick_text_row(payload):
    for row in (payload or {}).get("model_remains", []):
        if row.get("model_name") == MM_TEXT_MODEL:
            return row
    return None

def _mm_to_rate_limits(row):
    """Map a MiniMax-M* row onto Claude Code's rate_limits shape."""
    out = {}
    total = row.get("current_interval_total_count") or 0
    used  = row.get("current_interval_usage_count") or 0
    if total > 0:
        pct = used / total * 100.0
        resets_at = int(time.time()) + int((row.get("remains_time") or 0) / 1000)
        out["five_hour"] = {"used_percentage": pct, "resets_at": resets_at}
    w_total = row.get("current_weekly_total_count") or 0
    w_used  = row.get("current_weekly_usage_count") or 0
    if w_total > 0:
        w_pct = w_used / w_total * 100.0
        w_reset = int((row.get("weekly_end_time") or 0) / 1000)
        out["seven_day"] = {"used_percentage": w_pct, "resets_at": w_reset}
    return out

base_url = os.environ.get("ANTHROPIC_BASE_URL", "")
api_key  = os.environ.get("ANTHROPIC_API_KEY", "")
if "minimax.io" in base_url and api_key:
    MM_PREFIX = "MM "
    payload, mtime = _mm_load_cache()
    if not payload or (time.time() - mtime) > MM_TTL:
        try:
            fresh = _mm_fetch(api_key)
            if isinstance(fresh, dict) and fresh.get("base_resp", {}).get("status_code", 0) == 0:
                _mm_save_cache(fresh)
                payload = fresh
        except Exception:
            pass  # keep stale payload if any
    row = _mm_pick_text_row(payload) if payload else None
    mm_rate = _mm_to_rate_limits(row) if row else {}
    # Merge synthetic rate_limits into the inbound data, preserving context_window
    try:
        _data = json.loads(data_str) if data_str else {}
    except Exception:
        _data = {}
    if mm_rate:
        _data["rate_limits"] = mm_rate
    data_str = json.dumps(_data)

# ── Translations ──────────────────────────────────────────────
T = {
    "en": {
        "waiting":   "Waiting for first response...",
        "reset_now": "reset now",
        "na":        "N/A",
        "5h":        "5h",
        "7d":        "7d",
        "ctx":       "ctx",
        "reset":     "reset",
        "days":      "d",
        "hours":     "h",
        "minutes":   "m",
    },
    "it": {
        "waiting":   "In attesa della prima risposta...",
        "reset_now": "reset ora",
        "na":        "N/A",
        "5h":        "5h",
        "7d":        "7d",
        "ctx":       "ctx",
        "reset":     "reset",
        "days":      "g",
        "hours":     "h",
        "minutes":   "m",
    },
}

# Fallback to English for unknown languages
t = T.get(lang, T["en"])

try:
    data = json.loads(data_str)
except Exception:
    print(f"[ {t['waiting']} ]")
    sys.exit(0)

# ── ANSI colors ───────────────────────────────────────────────
GREEN  = "\033[32m"
ORANGE = "\033[38;5;208m"
RED    = "\033[31m"
CYAN   = "\033[36m"
BOLD   = "\033[1m"
DIM    = "\033[2m"
RESET  = "\033[0m"

FILLED = "\u2588"   # █
EMPTY  = "\u2591"   # ░

# ── Helpers ───────────────────────────────────────────────────
def bar(pct, length=8):
    try:
        v = float(pct)
        filled = int(v / 100 * length)
        return FILLED * filled + EMPTY * (length - filled)
    except Exception:
        return EMPTY * length

def color_rate(pct):
    """Rate limits — orange ≥80%, red ≥90%"""
    try:
        v = float(pct)
    except Exception:
        return f"{DIM}{t['na']}{RESET}"
    c = RED if v >= 90 else ORANGE if v >= 80 else GREEN
    return f"{c}{bar(v)} {v:.0f}%{RESET}"

def color_ctx(pct):
    """Context window — orange ≥70%, red >80%"""
    try:
        v = float(pct)
    except Exception:
        return f"{DIM}{t['na']}{RESET}"
    c = RED if v > 80 else ORANGE if v >= 70 else GREEN
    return f"{c}{bar(v)} {v:.0f}%{RESET}"

def time_until(ts):
    try:
        diff = int(ts) - int(datetime.datetime.now().timestamp())
        if diff <= 0:
            return f"{GREEN}{t['reset_now']}{RESET}"
        h_total = diff // 3600
        m       = (diff % 3600) // 60
        d_      = t['days']
        h_      = t['hours']
        m_      = t['minutes']
        if h_total >= 24:
            d, h = h_total // 24, h_total % 24
            return f"{CYAN}{d}{d_} {h}{h_}{RESET}"
        return f"{CYAN}{h_total}{h_} {m}{m_}{RESET}" if h_total > 0 else f"{CYAN}{m}{m_}{RESET}"
    except Exception:
        return f"{DIM}?{RESET}"

# ── Data extraction ───────────────────────────────────────────
rate = data.get("rate_limits", {})
fh   = rate.get("five_hour", {})
sd   = rate.get("seven_day", {})
ctx  = data.get("context_window", {})

fh_pct, fh_reset = fh.get("used_percentage"), fh.get("resets_at")
sd_pct, sd_reset = sd.get("used_percentage"), sd.get("resets_at")
ctx_pct          = ctx.get("used_percentage")

# ── Build output ──────────────────────────────────────────────
parts = []

if fh_pct is not None:
    reset_str = f" {t['reset']} {time_until(fh_reset)}" if fh_reset else ""
    parts.append(f"{BOLD}{t['5h']}:{RESET} {color_rate(fh_pct)}{reset_str}")
else:
    parts.append(f"{DIM}{t['5h']}: {t['na']}{RESET}")

if sd_pct is not None:
    reset_str = f" {t['reset']} {time_until(sd_reset)}" if sd_reset else ""
    parts.append(f"{BOLD}{t['7d']}:{RESET} {color_rate(sd_pct)}{reset_str}")
else:
    parts.append(f"{DIM}{t['7d']}: {t['na']}{RESET}")

if ctx_pct is not None:
    parts.append(f"{BOLD}{t['ctx']}:{RESET} {color_ctx(ctx_pct)}")

sep = f"  {DIM}|{RESET}  "
prefix = f"{BOLD}{CYAN}{MM_PREFIX}{RESET}" if MM_PREFIX else ""
print(prefix + sep.join(parts))
PYEOF
