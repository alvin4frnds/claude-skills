---
name: slack-notify
description: Notify the user on BOTH Slack and Anthropic's mobile push, with the active Remote Control session URL appended so they can click through and command the same local session back. Triggers on "notify me on slack", "slack me", "ping me on slack", "let me know via slack", "notify me when". AUTO-DETECTS Remote Control state by reading the bridge_status event in the session JSONL — never asks the user. The same URL works as a desktop browser link AND a mobile app universal link (assume Claude app installed). Uses the slack MCP server's conversations_add_message tool for the Slack post; mobile push fires automatically when Remote Control is active. If RC is off, posts Slack-only and surfaces a loud terminal action block telling the user how to flip the toggle.
---

# slack-notify — push a notification to Slack + Anthropic mobile, with remote-control deep-link

This skill is invoked when the user asks Claude to send them a notification — typically because they're walking away from the terminal and want to be pinged when something happens (tests pass, build finishes, work needs a decision).

The point: ping the user on **two channels at once** — Slack (because they live there during the workday) and Anthropic's mobile push (because it's first-party and tied to Remote Control) — and include a *clickable way back into this session* so the user can reply by driving the session via Remote Control.

## Required prerequisites

The user must already have:

1. **The slack MCP server installed and connected** — exposes `mcp__slack__conversations_add_message` and `mcp__slack__channels_list`. Verify the tools are available before trying to post.
2. **A self-DM channel** with the bot — typically `@<bot_username>` (e.g. `@claude_mcp_praveen` for the Crackle workspace).
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
   - If `content` indicates RC has been turned off, or there's no `bridge_status` event at all, RC is OFF.

4. Branch:
   - **RC ON** → use the URL in the Slack message and let the mobile-push framing fire. Skip the `⚠️` action block.
   - **RC OFF** → omit the URL, append the local-session footer to the Slack message, and surface the `⚠️` action block in the terminal (per step 6).

The same URL (`https://claude.ai/code/session_<id>`) works as both:
- A web link in a desktop browser → opens claude.ai/code
- A universal/app link on iOS or Android → opens directly in the Claude app (assume the user has it installed)

So one URL is enough. No separate `claude://` scheme needed.

### 3. Post via the Slack MCP tool

Call `mcp__slack__conversations_add_message`:

- `channel_id`: the user's self-DM with the bot. Format `@<bot_username>` works, e.g. `@claude_mcp_praveen`. If you don't know the bot username, ask the user once and remember it.
- `text`: the composed message + URL/note, formatted as below.
- `content_type`: `text/markdown`.

### 4. Message format

With remote control on (URL detected from JSONL):

```
🔔 <notification text>

<remote-control-url>
```

**Critical:** put the URL on its own line, with NO trailing characters and a blank line after. Do not append parenthetical helper text on the next line — Slack's link parser greedily extends URLs into adjacent characters and the resulting deep-link breaks ("untitled session, loading messages" stuck). Don't use markdown link syntax `[label](url)` either; the bare URL is the most reliable shape across Slack desktop, Slack mobile, and the iOS/Android Claude app universal-link handoff.

Without remote control:

```
🔔 <notification text>

_(local session — reply by returning to the terminal)_
```

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

- `✓ Slack: posted to @<bot>`
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

- **Multiple Slack workspaces.** If the user has more than one Slack MCP server connected (rare), ask which workspace before posting.
- **User asks for a channel post instead of DM.** Default is DM (push to *you*). If the user explicitly says "post in #channel", honor it — but warn that the bot needs to be `/invite`d to that channel first, or the post will fail with `not_in_channel`.
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
