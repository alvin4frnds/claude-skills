---
name: slack-notify
description: Notify the user on BOTH Slack and Anthropic's mobile push, with the active Remote Control session URL appended so they can click through and command the same local session back. Triggers on "notify me on slack", "slack me", "ping me on slack", "let me know via slack", "notify me when". AUTO-DETECTS Remote Control state by reading the bridge_status event in the session JSONL — never asks the user. The same URL works as a desktop browser link AND a mobile app universal link (assume Claude app installed). Appends a pipe-separated status trailer (branch | path) on a new line after the URL, mirroring the user's terminal status line. Posts via the @Claude MCP bot token (xoxb) through slack-bot-notify.sh — the only identity that actually push-notifies the user, since every user-token Slack connector posts AS the user and Slack never notifies you of your own messages. Mobile push fires automatically when Remote Control is active. If RC is off, posts Slack-only and surfaces a loud terminal action block telling the user how to flip the toggle.
---

# slack-notify — push a notification to Slack + Anthropic mobile, with remote-control deep-link

This skill is invoked when the user asks Claude to send them a notification — typically because they're walking away from the terminal and want to be pinged when something happens (tests pass, build finishes, work needs a decision).

The point: ping the user on **two channels at once** — Slack (because they live there during the workday) and Anthropic's mobile push (because it's first-party and tied to Remote Control) — and include a *clickable way back into this session* so the user can reply by driving the session via Remote Control.

## Required prerequisites

The user must already have:

1. **The @Claude MCP bot token** saved at `~/.claude/.slack_xure_bot_token` (an `xoxb-…` token for the `@Claude MCP` bot, `U0B2W0ARS5P`, in the **Xure / xure-solutions** workspace, team `T05MJ9YFFAN`). The posting helper `slack-bot-notify.sh` (next to this file) reads it. **Do NOT use any `mcp__slack__*` / claude.ai Slack connector to post a notification** — those log in AS the user, and Slack never notifies you of your own messages (learned the hard way 2026-06-07). The bot is a *different* identity, so its DM actually pings the user.
   - Verify before posting: `[ -r ~/.claude/.slack_xure_bot_token ]`. If missing, tell the user the bot token isn't set up and stop — don't silently fall back to a user-token connector (it won't notify).
2. **Recipient = the user's Xure user_id** `U05MBLHE2J2` (`praveen.kumar`). `slack-bot-notify.sh` defaults to this; override with `SLACK_NOTIFY_USER`.
3. **Remote Control active** — required for mobile push and the clickable reply URL. Skill auto-detects state per step 2; if off, falls back to Slack-only and surfaces the `⚠️` action block (step 6) every invocation.
   - The Claude mobile app is **assumed installed and signed in** to the same Anthropic account as the CLI; do not surface "install the app" hints.
   - `Push when Claude decides` should be enabled via `/config` for mobile push to actually fire (this is checked once: if the user reports never receiving mobile pushes despite RC being on, suggest checking `/config`).

   **Tip — make Remote Control default-on so you never have to remember the flag:**

   The user typically launches Claude Code via a shell alias (`cl`, `clc`, etc.). The cleanest setup is:
   - **Add `--remote-control` to that alias** — e.g., `alias cl='claude --remote-control'` (bash/zsh) or, on Windows PowerShell, a function: `function cl { claude --remote-control @args }`. Every session then starts RC-enabled.
   - **Or** run `/config` once and toggle **Enable Remote Control for all sessions** to `true` — same effect, no alias edits.

If the slack tool isn't available, tell the user it isn't loaded and stop. Do not silently no-op.

## Procedure

### 1. Compose the notification text

Start from what the user asked you to convey. Examples:

- "tests passed on the auth refactor — 142 green, 0 failed"
- "ran into a permission prompt — need approval to delete `logs/old/`"
- "draft PR opened: https://github.com/.../pulls/42"

Keep it tight. One paragraph max. The user is on their phone or in another window — they're scanning, not reading.

### 2. Auto-detect Remote Control state and URL — never ask the user

Do not ask. Detect it programmatically every invocation. The harness writes a `system / bridge_status` event into the session JSONL when `/remote-control` (or `--remote-control`) is enabled.

**Procedure** (use Bash or PowerShell — pick whichever is available):

1. Read the current session ID from the env var:
   ```powershell
   $sid = $env:CLAUDE_CODE_SESSION_ID
   ```
   ```bash
   sid="$CLAUDE_CODE_SESSION_ID"
   ```
   If unset, fall back to "RC unknown" — proceed to Case OFF below.

2. Locate the JSONL — the harness writes it to `~/.claude/projects/<project-slug>/<session-id>.jsonl`. The slug encoding is harness-specific, so just glob across all project dirs:
   ```powershell
   $jsonl = Get-ChildItem "$env:USERPROFILE\.claude\projects\*\$sid.jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1
   ```
   ```bash
   jsonl=$(ls ~/.claude/projects/*/"$sid".jsonl 2>/dev/null | head -1)
   ```

3. Find the **most recent** `bridge_status` event and extract the URL. Use Grep on the JSONL with the pattern `"subtype":"bridge_status"`. Read the last matching line. The line is a JSON object with `"content"` and `"url"` fields — for example:
   ```json
   {"type":"system","subtype":"bridge_status","content":"/remote-control is active. Code in CLI or at https://claude.ai/code/session_01AgjnbPSQQ6m9RbuJx76R3P","url":"https://claude.ai/code/session_01AgjnbPSQQ6m9RbuJx76R3P",...}
   ```
   - If `content` contains `is active`, RC is ON. Use the `url` field for the deep link.
   - If `content` indicates RC has been turned off, RC is OFF.
   - **Caveat (seen on Claude Code 2.1.168, 2026-06-07):** some builds write **no** `bridge_status` event into the JSONL even when RC is on, so "no event found" does **not** prove RC is off — and the real deep-link URL is then unrecoverable from the log (the only `session_01…` string present is the *example* in this very skill file — never paste that). If you find no event, don't assert RC is off; treat RC as *unknown*, omit the URL line, still frame the mobile-push moment (it fires from RC regardless), and skip the loud `⚠️` block unless the user has told you RC is off.

4. Branch:
   - **RC ON** → use the URL in the Slack message and let the mobile-push framing fire. Skip the `⚠️` action block.
   - **RC OFF** → omit the URL, append the local-session footer to the Slack message, and surface the `⚠️` action block in the terminal (per step 6).

The same URL (`https://claude.ai/code/session_<id>`) works as both:
- A web link in a desktop browser → opens claude.ai/code
- A universal/app link on iOS or Android → opens directly in the Claude app (assume the user has it installed)

So one URL is enough. No separate `claude://` scheme needed.

### 3. Post via the bot helper script

Call the helper next to this skill — it DMs the user **as the @Claude MCP bot** (the only identity that push-notifies them):

```bash
~/.claude/skills/slack-notify/slack-bot-notify.sh "$(cat <<'EOF'
🔔 <notification text>

<remote-control-url-if-RC-on>

<branch> | <last-3-dirs>
EOF
)"
```

- It reads the `xoxb` token from `~/.claude/.slack_xure_bot_token`, opens the IM with `U05MBLHE2J2`, and posts. On success it prints `OK ts=… channel=…`; on failure `ERROR: …` (surface that to the user).
- The message uses **Slack mrkdwn**, not full markdown: `*bold*`, `_italic_`, `` `code` ``, `>quote`. (Note: `*single asterisks*` for bold, not `**double**`.)
- Do **not** use a `mcp__slack__*` tool or the claude.ai Slack connector here — they post as the user and won't notify. If the token file is missing, say so and stop.

### 4. Message format

With remote control on (URL detected from JSONL):

```
🔔 <notification text>

<remote-control-url>

<branch> | <last-3-dirs>
```

Without remote control:

```
🔔 <notification text>

<branch> | <last-3-dirs>

_(local session — reply by returning to the terminal)_
```

**Critical for the URL line:** put the URL on its own line, with NO trailing characters and a blank line after. Do not append parenthetical helper text on the next line — Slack's link parser greedily extends URLs into adjacent characters and the resulting deep-link breaks ("untitled session, loading messages" stuck). Don't use markdown link syntax `[label](url)` either; the bare URL is the most reliable shape across Slack desktop, Slack mobile, and the iOS/Android Claude app universal-link handoff.

**Status trailer (the last line):** mirrors the user's terminal status line. Two fields, pipe-separated:

- **`<branch>`** — `git --no-optional-locks branch --show-current` run from the session's cwd. Falls back to `no-branch` if not inside a repo.
- **`<last-3-dirs>`** — last 3 path components of cwd, slash-joined (e.g. `Code/Learning/awesome-claude-skills`).

The **`plan`** field was dropped (2026-06-07, at the user's request). On this Mac the live `5h%/7d%` numbers exist only in the statusline command's stdin (`rate_limits`, fed by the harness) — a background tool can't read them and they aren't cached on disk, so the field always came out `plan: ?`. Don't reintroduce it or fake it. The context-window field is likewise omitted — only meaningful in the live terminal.

Use 🔔 as the lead emoji to make notifications visually distinct from other Slack messages. If the message is good news (tests passed, deploy succeeded), swap to ✅. If it's blocking (waiting on the user, error needing decision), use ⚠️.

### 5. Trigger mobile push alongside the Slack post

Anthropic's mobile push system is **not a tool** — there's no `push_to_mobile()` call. It's an automatic classifier that fires when:

- Remote Control is active for the current session, AND
- Claude reaches a moment that warrants user attention (long task done, decision needed, explicit "notify me" request)

The skill being invoked *is* such a moment. To make the push reliably fire, after the Slack post, in your normal terminal output frame the result with explicit notification language. For example:

> Notification sent. Tests passed (142 green, 0 failed) — user should be notified on Slack and via mobile push.

The exact wording doesn't matter; what matters is that the moment is unambiguously a user-notification event in the session transcript. Anthropic's classifier looks at session signals to decide push timing, and a clearly-framed notification moment is the most reliable trigger.

If Remote Control is off, mobile push cannot fire — Anthropic's push system requires an active Remote Control session as the addressing mechanism. In that case, only Slack goes out, and your terminal output should note: `Mobile push skipped — no active Remote Control session.`

### 6. Confirm in the local terminal

Output one short line per channel that fired:

- `✓ Slack: DM'd as @Claude MCP bot (ts <ts>)` — using the `ts` the helper printed
- `✓ Mobile push: triggered (Remote Control active)` *or* `– Mobile push: skipped (no Remote Control)`

**If Remote Control is OFF for this session**, append the following block to your terminal output — **every invocation, not throttled, not buried as a tip**. The user explicitly wants to be told, plainly, each time, that one toggle would unlock the second channel:

```
⚠️  Remote Control is off — you're getting Slack only.

To also get mobile push and a clickable reply URL in the message, flip ONE of these:
  1. Mid-session: type  /remote-control     (enables for this session only)
  2. Persistent:  /config → toggle "Enable Remote Control for all sessions" → true
  3. Alias:       add --remote-control to your `cl` shell function
                  (PS profile: function cl { claude --dangerously-skip-permissions --chrome --remote-control })
```

The choice of three is intentional: option 1 is for *right now*, option 2 is the no-friction default-on, option 3 is for users who relaunch from a shell alias. Show all three; let the user pick.

(Mobile app is assumed installed — don't bother the user about that. If they ever say mobile push isn't firing despite RC being on, suggest enabling `Push when Claude decides` in `/config` once.)

## Edge cases

- **Why not the user's own Slack connectors.** The user also has a `claude.ai Slack` connector on the `crackle-world` workspace and may reconnect others — they all authenticate AS the user and so can't push-notify him. Always go through the **Xure bot** (`slack-bot-notify.sh`), regardless of what other Slack tools are connected.
- **User asks for a channel post instead of DM.** Default is the DM. If the user explicitly says "post in #channel", pass that channel ID via `SLACK_NOTIFY_USER` is not right — instead call `chat.postMessage` with the channel ID directly using the same token; but the `@Claude MCP` bot must be `/invite`d to that channel first, or it fails with `not_in_channel`.
- **URL changes mid-session.** If the user toggles `/remote-control` again or the URL rotates, the JSONL gets a fresh `bridge_status` event. Always read the *most recent* one — never cache the URL across invocations.
- **Notification spam risk.** This skill is invoked explicitly. Don't post unsolicited Slack messages just because Claude finished a turn — that's the job of mobile push or hooks, not this skill.

## Why this skill exists (design intent)

The user's workflow:
1. Start a Claude Code session locally with `--remote-control` (or enable mid-session).
2. Walk away from the terminal.
3. Get pings on **two channels** when something happens:
   - **Slack DM** — works at desk in front of computer, where their workday lives.
   - **Mobile push** — works when phone is the only nearby surface (couch, away from desk, walking).
4. Tap either notification → land in `claude.ai/code` → drive the same session.

Slack and mobile push aren't redundant — they cover different physical contexts. Both firing means whichever surface the user happens to be on, they see the ping.

The skill uses Slack via MCP for the **outbound push**, and signals to Anthropic's mobile push classifier so a phone notification fires too. The actual *reply* path for both is Anthropic's Remote Control, which handles auth, session resume, conversation sync, and the rest. We don't try to build a Slack-to-Claude bridge — we just make the URL one click away from either notification surface.
