---
name: slack-notify
description: Notify the user on BOTH Slack and Anthropic's mobile push, with the active Remote Control session URL appended so they can click through and command the same local session back. Triggers on "notify me on slack", "slack me", "ping me on slack", "let me know via slack", "notify me when". Uses the slack MCP server's conversations_add_message tool for the Slack post; mobile push fires automatically when Remote Control is active (Anthropic's classifier picks up the explicit "this is a user notification moment" framing). If remote-control is off, posts to Slack only with a note that the session is local-only.
---

# slack-notify — push a notification to Slack + Anthropic mobile, with remote-control deep-link

This skill is invoked when the user asks Claude to send them a notification — typically because they're walking away from the terminal and want to be pinged when something happens (tests pass, build finishes, work needs a decision).

The point: ping the user on **two channels at once** — Slack (because they live there during the workday) and Anthropic's mobile push (because it's first-party and tied to Remote Control) — and include a *clickable way back into this session* so the user can reply by driving the session via Remote Control.

## Required prerequisites

The user must already have:

1. **The slack MCP server installed and connected** — exposes `mcp__slack__conversations_add_message` and `mcp__slack__channels_list`. Verify the tools are available before trying to post.
2. **A self-DM channel** with the bot — typically `@<bot_username>` (e.g. `@claude_mcp_praveen` for the Crackle workspace).
3. **For mobile push to also fire** (recommended, but skill still works without):
   - Claude Code v2.1.110+
   - Remote Control active in the current session (`claude --remote-control` or `/remote-control`)
   - Claude mobile app installed (iOS or Android), signed in to the same Anthropic account as the CLI
   - `Push when Claude decides` enabled via `/config` in Claude Code

   If the user hasn't set these up, the Slack post still goes out — mobile push just won't fire. Mention the missing setup in your terminal confirmation so the user can fix it next time.

If the slack tool isn't available, tell the user it isn't loaded and stop. Do not silently no-op.

## Procedure

### 1. Compose the notification text

Start from what the user asked you to convey. Examples:

- "tests passed on the auth refactor — 142 green, 0 failed"
- "ran into a permission prompt — need approval to delete `logs/old/`"
- "draft PR opened: https://github.com/.../pulls/42"

Keep it tight. One paragraph max. The user is on their phone or in another window — they're scanning, not reading.

### 2. Detect / collect the remote-control session URL

Three cases:

**Case A — Remote control is on AND the user has shared the URL with you this session.**
Use the stored URL. (You'll have stored it earlier; see step 3.)

**Case B — Remote control is on but URL is unknown.**
Ask the user once, in one short sentence: "What's the remote-control URL/session name? (paste from the terminal output where you ran `/remote-control`)". Store the answer for the rest of the session — every subsequent slack-notify reuses it without re-asking.

**Case C — Remote control is off.**
Don't ask, don't make one up. Post the message but append a one-line note: `_(local session — to reply, come back to your terminal or run `/remote-control` to enable web/mobile access)_`.

You cannot detect remote-control state programmatically — there's no env var. Trust what the user has told you. If they haven't said either way, ask once: "Is remote control enabled for this session?" and remember the answer.

### 3. Post via the Slack MCP tool

Call `mcp__slack__conversations_add_message`:

- `channel_id`: the user's self-DM with the bot. Format `@<bot_username>` works, e.g. `@claude_mcp_praveen`. If you don't know the bot username, ask the user once and remember it.
- `text`: the composed message + URL/note, formatted as below.
- `content_type`: `text/markdown`.

### 4. Message format

With remote control URL:

```
🔔 <notification text>

💬 Reply: <remote-control-url>
```

With session name only (no deep link):

```
🔔 <notification text>

💬 Reply: open https://claude.ai/code and pick session "<name>"
```

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

If the user hasn't set up mobile push prerequisites (e.g., never enabled `/config` push, no mobile app), add a one-time hint: `Tip: enable "Push when Claude decides" in /config to also get mobile pings.` Don't repeat the hint every invocation — once per session is enough.

## Edge cases

- **Multiple Slack workspaces.** If the user has more than one Slack MCP server connected (rare), ask which workspace before posting.
- **User asks for a channel post instead of DM.** Default is DM (push to *you*). If the user explicitly says "post in #channel", honor it — but warn that the bot needs to be `/invite`d to that channel first, or the post will fail with `not_in_channel`.
- **URL changes mid-session.** If the user runs `/remote-control` again or the URL rotates, they'll usually paste the new one. Replace the stored URL when given a new one without asking.
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
