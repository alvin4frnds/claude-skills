# Claude Code Statusline Setup (Mac)

Portable setup doc. Copy this file to your Mac, then either follow the steps manually or hand it to Claude Code and say "set this up".

Statusline format:
```
<branch> | <last 3 dirs of cwd> | context left: <k>/<k> (<%>) | plan: <%> | resets in <h m>
```

---

## 1. Prerequisites

```bash
# Python 3 (preinstalled on macOS, but ensure it's on PATH)
python3 --version

# Required Python package for the plan/usage fetch
python3 -m pip install --user curl_cffi
```

If `pip` isn't available: `python3 -m ensurepip --user`.

---

## 2. Create `~/.claude/settings.json`

If the file exists, merge the `statusLine` block into it. Otherwise create it.

```json
{
  "permissions": {
    "defaultMode": "auto"
  },
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-command.sh"
  },
  "effortLevel": "xhigh",
  "skipDangerousModePermissionPrompt": true,
  "skipAutoPermissionPrompt": true
}
```

> Only the `statusLine` block is required for the statusline. The other keys are my personal preferences — keep or drop as you like.

---

## 3. Create `~/.claude/statusline-command.sh`

```bash
#!/usr/bin/env bash
# Claude Code statusLine command
# Displays: git branch | last 3 dirs | ctx remaining | plan | resets

input=$(cat)

# --- 1. Git branch ---
cwd=$(printf '%s' "$input" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print((d.get('workspace') or {}).get('current_dir') or d.get('cwd') or '.')
" 2>/dev/null)
branch=$(git -C "${cwd:-.}" --no-optional-locks branch --show-current 2>/dev/null)
[ -z "$branch" ] && branch="no-branch"

# --- Parse context_window fields ---
parsed=$(printf '%s' "$input" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
cw = d.get('context_window') or {}
rp  = cw.get('remaining_percentage')
cs  = cw.get('context_window_size')
print('' if rp is None else str(rp))
print('' if cs is None else str(cs))
" 2>/dev/null)

remaining_pct=$(echo "$parsed" | sed -n '1p')
ctx_size=$(echo "$parsed"      | sed -n '2p')

# --- Context remaining ---
if [ -n "$remaining_pct" ] && [ -n "$ctx_size" ]; then
  remaining_part=$(python3 -c "
rem_k = $ctx_size * $remaining_pct / 100 / 1000
cs_k  = $ctx_size / 1000
print('context left: %.1fk/%.0fk (%.1f%%)' % (rem_k, cs_k, $remaining_pct))
")
else
  remaining_part="context left: no data"
fi

# --- Plan usage ---
plan_part=$(python3 "$HOME/.claude/claude_usage.py" 2>/dev/null)
[ -z "$plan_part" ] && plan_part="plan: ?"

# --- Last 3 directory components of cwd ---
last3dirs=$(STATUSLINE_CWD="${cwd:-.}" python3 -c "
import os
path = os.environ.get('STATUSLINE_CWD', '.')
parts = [p for p in path.split('/') if p]
print('/'.join(parts[-3:]) if len(parts) >= 3 else '/'.join(parts))
" 2>/dev/null)
[ -z "$last3dirs" ] && last3dirs="?"

printf "%s | %s | %s | %s" "$branch" "$last3dirs" "$remaining_part" "$plan_part"
```

Make it executable:
```bash
chmod +x ~/.claude/statusline-command.sh
```

---

## 4. Create `~/.claude/claude_usage.py`

```python
#!/usr/bin/env python3
"""Fetch Claude plan session usage for statusline. Unofficial — may break."""
import json, time
from datetime import datetime, timezone
from pathlib import Path
from curl_cffi import requests as creq

HOME = Path.home()
KEY_FILE = HOME / ".claude" / "claude_session_key.txt"
ORG_FILE = HOME / ".claude" / "claude_org_id.txt"
CACHE = HOME / ".claude" / "claude_usage_cache.json"
CACHE_TTL = 150

def fmt_remaining(iso):
    try:
        r = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        secs = (r - datetime.now(timezone.utc)).total_seconds()
        if secs <= 0:
            return "resetting"
        h, m = int(secs // 3600), int((secs % 3600) // 60)
        return f"{h}h {m}m" if h else f"{m}m"
    except Exception:
        return "?"

def http_get(url, cookie):
    r = creq.get(url, cookies={"sessionKey": cookie}, impersonate="chrome131", timeout=8)
    return r.json()

def get_org(cookie):
    if ORG_FILE.exists():
        return ORG_FILE.read_text().strip()
    orgs = http_get("https://claude.ai/api/organizations", cookie)
    org_id = orgs[0]["uuid"]
    ORG_FILE.write_text(org_id)
    return org_id

def fetch():
    cookie = KEY_FILE.read_text().strip()
    org_id = get_org(cookie)
    u = http_get(f"https://claude.ai/api/organizations/{org_id}/usage", cookie)
    fh = u.get("five_hour") or {}
    util, resets = fh.get("utilization"), fh.get("resets_at")
    if util is None:
        return "plan: ?"
    return f"plan: {util:.0f}% | resets in {fmt_remaining(resets)}"

def main():
    try:
        d = json.loads(CACHE.read_text())
        if time.time() - d["t"] < CACHE_TTL:
            print(d["s"], end=""); return
    except Exception:
        pass
    try:
        s = fetch()
        CACHE.write_text(json.dumps({"t": time.time(), "s": s}))
    except Exception:
        s = "plan: err"
    print(s, end="")

if __name__ == "__main__":
    main()
```

---

## 5. Add your claude.ai session key

The plan/usage portion needs your claude.ai `sessionKey` cookie:

1. Open https://claude.ai in a browser while logged in.
2. DevTools → Application → Cookies → `https://claude.ai` → copy the value of `sessionKey` (starts with `sk-ant-sid01-...`).
3. Save it:
   ```bash
   echo "<paste-sessionKey-value>" > ~/.claude/claude_session_key.txt
   chmod 600 ~/.claude/claude_session_key.txt
   ```

The org ID auto-populates on first run into `~/.claude/claude_org_id.txt`.

> If the cookie expires, the statusline shows `plan: err` — refresh `claude_session_key.txt`.

---

## 6. Verify

```bash
# Should print something like: "plan: 12% | resets in 3h 24m"
python3 ~/.claude/claude_usage.py

# Smoke-test the script with a fake Claude payload
echo '{"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"remaining_percentage":80,"context_window_size":1000000}}' \
  | bash ~/.claude/statusline-command.sh
```

Then start Claude Code in any repo — the statusline should appear at the bottom.

---

## Differences from the Windows setup

| Windows | Mac |
|---|---|
| `bash /c/Users/Praveen/.claude/statusline-command.sh` | `bash ~/.claude/statusline-command.sh` |
| `python "C:/Users/Praveen/.claude/claude_usage.py"` | `python3 "$HOME/.claude/claude_usage.py"` |
| Path separator handling for `C:\Users\...` | Not needed — POSIX paths only |
| `python` interpreter | `python3` interpreter |

Everything else is identical.
