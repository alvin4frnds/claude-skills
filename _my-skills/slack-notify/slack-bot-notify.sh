#!/usr/bin/env bash
# slack-bot-notify.sh — DM Praveen on Slack AS the @Claude MCP bot (Xure workspace).
#
# WHY this exists: every Slack MCP connector available logs in AS Praveen
# (his own user token), and Slack NEVER notifies you about your own messages.
# The only way to actually push-notify him is to post from a DIFFERENT identity —
# the @Claude MCP bot (U0B2W0ARS5P) in the Xure / xure-solutions workspace.
#
# Usage:   slack-bot-notify.sh "message text"
#     or:  printf '%s' "message text" | slack-bot-notify.sh
# Exit 0 + "OK ts=… channel=…" on success; non-zero + "ERROR: …" on failure.
#
# Config (overridable via env):
#   SLACK_BOT_TOKEN_FILE  default ~/.claude/.slack_xure_bot_token  (xoxb, chmod 600)
#   SLACK_NOTIFY_USER     default U05MBLHE2J2  (praveen.kumar in Xure)
set -euo pipefail

TOKEN_FILE="${SLACK_BOT_TOKEN_FILE:-$HOME/.claude/.slack_xure_bot_token}"
RECIPIENT="${SLACK_NOTIFY_USER:-U05MBLHE2J2}"

[ -r "$TOKEN_FILE" ] || { echo "ERROR: bot token file not found/readable: $TOKEN_FILE" >&2; exit 1; }
tok=$(cat "$TOKEN_FILE")

if [ "$#" -ge 1 ]; then msg="$1"; else msg=$(cat); fi
[ -n "$msg" ] || { echo "ERROR: empty message" >&2; exit 1; }

# --- Desktop widget side-channel -------------------------------------------
# Also publish to ntfy so the native "Claude Reminders" desktop widget updates.
# Best-effort: wrapped so it can NEVER fail the Slack notification below. Slack
# remains the phone-push path; ntfy only drives the widget.
NTFY_CFG="${NTFY_CONFIG_FILE:-$HOME/.claude/slack-ping-tray/ntfy.json}"
if [ -r "$NTFY_CFG" ]; then
  MSG="$msg" CFG="$NTFY_CFG" python3 - >/dev/null 2>&1 <<'PY' || true
import os, json, re, time, urllib.request
try:
    cfg = json.load(open(os.environ["CFG"]))
    base, topic, token = cfg["base_url"].rstrip("/"), cfg["topic"], cfg["token"]
    msg = os.environ["MSG"]
    lines = [l for l in msg.splitlines() if l.strip()]
    text = lines[0] if lines else msg
    low = text.lower()
    action = text.lstrip().startswith(("⚠", "🚨", "❌", "🔴", "🔔")) or \
             any(k in low for k in ("needs your input", "needs input", "waiting for", "question"))
    payload = {"type": "action" if action else "fyi", "text": text, "ts": int(time.time())}
    m = re.search(r"https://claude\.ai/code/\S+", msg)
    if m:
        payload["session_url"] = m.group(0)
    req = urllib.request.Request(
        f"{base}/{topic}",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "text/plain; charset=utf-8"},
    )
    urllib.request.urlopen(req, timeout=6).read()
except Exception:
    pass
PY
fi
# ---------------------------------------------------------------------------

# Open (or fetch) the IM channel with the recipient.
chan=$(curl -s -H "Authorization: Bearer $tok" -H "Content-type: application/json" \
  -d "{\"users\":\"$RECIPIENT\"}" https://slack.com/api/conversations.open \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('channel',{}).get('id','') if d.get('ok') else '')")
[ -n "$chan" ] || { echo "ERROR: could not open DM with $RECIPIENT (check token/scopes)" >&2; exit 1; }

# Build JSON payload safely from env, post, and report ts/channel.
MSG="$msg" CHAN="$chan" python3 -c "import os,json;print(json.dumps({'channel':os.environ['CHAN'],'text':os.environ['MSG'],'unfurl_links':False}))" \
  | curl -s -H "Authorization: Bearer $tok" -H "Content-type: application/json; charset=utf-8" \
      --data-binary @- https://slack.com/api/chat.postMessage \
  | python3 -c "import sys,json;d=json.load(sys.stdin);print('OK ts=%s channel=%s'%(d.get('ts'),d.get('channel')) if d.get('ok') else 'ERROR: '+str(d.get('error')))"
