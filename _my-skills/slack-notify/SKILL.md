---
name: slack-notify
description: Notify the user on BOTH Slack and Anthropic's mobile push, with the active Remote Control session URL appended so they can click through and command the same local session back. Triggers on "notify me on slack", "slack me", "ping me on slack", "let me know via slack", "notify me when". AUTO-DETECTS Remote Control state by reading the bridge_status event in the session JSONL — never asks the user. The same URL works as a desktop browser link AND a mobile app universal link (assume Claude app installed). Appends a pipe-separated status trailer (branch | path | plan) on a new line after the URL, mirroring the user's terminal status line. Uses the slack MCP server's conversations_add_message tool for the Slack post; mobile push fires automatically when Remote Control is active. If RC is off, posts Slack-only and surfaces a loud terminal action block telling the user how to flip the toggle.
---

# slack-notify — push a notification to Slack + Anthropic mobile, with remote-control deep-link

This skill is invoked when the user asks Claude to send them a notification — typically because they're walking away from the terminal and want to be pinged when something happens (tests pass, build finishes, work needs a decision).

The point: ping the user on **two channels at once** — Slack (because they live there during the workday) and Anthropic's mobile push (because it's first-party and tied to Remote Control) — and include a *clickable way back into this session* so the user can reply by driving the session via Remote Control.

## Required prerequisites

The user must already have:

1. **The slack MCP server installed and connected** — exposes `mcp__slack__conversations_add_message` and `mcp__slack__channels_list`. Verify the tools are available before trying to post.
2. **A self-DM channel** with the bot — addressed by **the user's Slack member ID** (e.g. `U05MBLHE2J2` for Praveen in workspace `T05MJ9YFFAN`). Do NOT use `@<bot_username>` — that resolves to the bot's self-DM and the user can't see it. Always post to the user's `U...` ID; Slack auto-creates/reuses the bot↔user IM channel.
3. **Remote Control active** — required for mobile push and the clickable reply URL. Skill auto-detects state per step 2; if off, falls back to Slack-only and surfaces the `⚠️` action block (step 6) every invocation.
   - The Claude mobile app is **assumed installed and signed in** to the same Anthropic account as the CLI; do not surface "install the app" hints.
   - `Push when Claude decides` should be enabled via `/config` for mobile push to actually fire (this is checked once: if the user reports never receiving mobile pushes despite RC being on, suggest checking `/config`).

   **Tip — make Remote Control default-on so you never have to remember the flag:**

   The user typically launches Claude Code via a shell alias (`cl`, `clc`, etc.). The cleanest setup is:
   - **Add `--remote-control` to that alias** — e.g., `alias cl='claude --remote-control'` (bash/zsh) or, on Windows PowerShell, a function: `function cl { claude --remote-control @args }`. Every session then starts RC-enabled.
   - **Or** run `/config` once and toggle **Enable Remote Control for all sessions** to `true` — same effect, no alias edits.

If the slack tool isn't available, tell the user it isn't loaded and stop. Do not silently no-op.

## Delegation model

Steps 1, 2, 5, 6 run on the parent (main thread / Opus). Steps 3–4 run inside a Sonnet sub-agent spawned via the Agent tool. The split keeps model judgment on the parent and pushes the rote shell + MCP work to a cheaper, predictable model.

| Step | Where | Why |
|---|---|---|
| 1. Compose notification text + pick emoji | Parent | Model judgment — phrasing, tone, good-news vs blocking. |
| 2. Detect Remote Control state | Parent | Parent already has the session env var; RC state drives both the agent's payload and whether the parent emits the mobile-push phrase. |
| 3. Assemble status trailer + post to Slack | **Sonnet sub-agent** | Deterministic shell + one MCP call. Keeps MCP noise out of the parent context. |
| 4. Format message | **Sonnet sub-agent** | The parent passes the agent the upper portion (emoji + text + URL); the agent fills in the trailer and posts the final string. |
| 5. Emit mobile-push trigger phrase | Parent | **CRITICAL** — the classifier reads the parent transcript. A phrase emitted inside a sub-agent becomes a tool_result string and may not register as a notification moment. |
| 6. Terminal confirmation block | Parent | The loud RC-off action block needs to land in the parent's user-facing output, not inside an agent result. |

Use the `general-purpose` subagent type (the only one with both `*` tool access and a model override). Pass `model: "sonnet"`. The agent prompt must be **self-contained** — sub-agents don't see the parent conversation, so the parent has to spell out the payload and the expected return shape.

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

### 3. Hand off to a Sonnet sub-agent — it assembles the trailer and posts

Spawn a `general-purpose` sub-agent with `model: "sonnet"` via the Agent tool. The agent's job: run the deterministic work (assemble the status trailer per step 4, call `mcp__slack__conversations_add_message`), then return a small status object.

**Channel ID — pass this in the agent prompt explicitly.** Use the user's Slack member ID (`U...`), not `@<bot_username>`. Posting to `@<bot>` lands in the bot's self-channel where the user can't see it. For Praveen in `T05MJ9YFFAN` use `U05MBLHE2J2`. Look up unknowns via `slack_get_users` **from the parent** (don't make the agent do user-directory lookups — that's wasted Sonnet effort on a one-time lookup the parent can cache).

**Worked example of the Agent call:**

````
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Post slack notification with status trailer",
  prompt: `
You are posting a Slack notification on behalf of the parent session. The parent has already composed the message and detected Remote Control state. Your job is to (a) assemble the status trailer and (b) post via the Slack MCP tool. Do not improvise — follow the steps below.

PAYLOAD (from parent):
- Emoji:               ✅
- Message body:        tests passed on the auth refactor — 142 green, 0 failed
- Remote Control URL:  https://claude.ai/code/session_01AgjnbPSQQ6m9RbuJx76R3P
- Remote Control state: on
- Channel ID:          U05MBLHE2J2

STEP A — Assemble status trailer (run shell from the parent's cwd, which you inherit):
- branch:        \`git --no-optional-locks branch --show-current\` (fallback: \`no-branch\`)
- last-3-dirs:   last 3 components of \`pwd\`, slash-joined (e.g. \`Code/Learning/awesome-claude-skills\`)
- plan:          \`python ~/.claude/claude_usage.py\` on macOS/Linux, \`python C:\\Users\\Praveen\\.claude\\claude_usage.py\` on Windows. Fallback: \`plan: ?\`.
- Trailer = \`<branch> | <last-3-dirs> | <plan>\`

STEP B — Format the final message per the template in the slack-notify skill's "Message format" section:
- If Remote Control state = on: emoji + body, blank line, URL on its own line, blank line, trailer.
- If Remote Control state = off: emoji + body, blank line, trailer, blank line, \`_(local session — reply by returning to the terminal)_\`.
- URL line: bare URL, no surrounding characters, no markdown link syntax.

STEP C — Call mcp__slack__conversations_add_message with:
  channel_id:    <Channel ID from payload>
  text:          <formatted message>
  content_type:  text/markdown

RETURN exactly this structure (no extra prose):
  posted:  true | false
  trailer: <the trailer string you assembled>
  error:   <empty if posted=true, else the failure reason>

Do NOT emit any "notification sent" framing or mobile-push language — the parent handles that.
`
})
````

The agent inherits the parent's cwd and env vars, so `git`, `python`, `~/.claude/claude_usage.py`, and the Slack MCP tool all resolve normally inside the sub-agent.

### 4. Message format (the sub-agent outputs this — spec is duplicated here for human auditability)

The sub-agent fills in the trailer and posts. The parent already passed it the emoji, body, URL, and RC state. This is the canonical format spec — keep it in the skill so a human reading the skill can verify what the agent is told to produce.

With remote control on (URL passed from parent):

```
🔔 <notification text>

<remote-control-url>

<branch> | <last-3-dirs> | <plan>
```

Without remote control:

```
🔔 <notification text>

<branch> | <last-3-dirs> | <plan>

_(local session — reply by returning to the terminal)_
```

**Critical for the URL line:** put the URL on its own line, with NO trailing characters and a blank line after. Do not append parenthetical helper text on the next line — Slack's link parser greedily extends URLs into adjacent characters and the resulting deep-link breaks ("untitled session, loading messages" stuck). Don't use markdown link syntax `[label](url)` either; the bare URL is the most reliable shape across Slack desktop, Slack mobile, and the iOS/Android Claude app universal-link handoff.

**Status trailer (the third line):** mirrors the user's terminal status line. Three fields, pipe-separated, pulled from the same sources as `statusline-command.sh`:

- **`<branch>`** — `git --no-optional-locks branch --show-current` run from the session's cwd. Falls back to `no-branch` if not inside a repo.
- **`<last-3-dirs>`** — last 3 path components of cwd, slash-joined (e.g. `Code/Learning/awesome-claude-skills`).
- **`<plan>`** — output of `python C:\Users\Praveen\.claude\claude_usage.py` (Windows) or whatever path the user's `claude_usage.py` is at on other OSes. Format is typically `plan: 86% | resets in 1h 11m`. If the script fails or is missing, fall back to `plan: ?`.

The context-window field is intentionally omitted from Slack — it's only meaningful in the live terminal where the harness injects token counts. Don't fake it.

Use 🔔 as the lead emoji to make notifications visually distinct from other Slack messages. If the message is good news (tests passed, deploy succeeded), swap to ✅. If it's blocking (waiting on the user, error needing decision), use ⚠️.

### 5. Trigger mobile push — parent thread only, after the sub-agent returns

**Do NOT delegate this step.** Anthropic's mobile push classifier reads the **parent** session transcript, not the contents of sub-agent results. A "Notification sent…" phrase emitted from inside the Sonnet agent becomes a tool_result string and may not register as a user-notification moment.

After the sub-agent returns `posted: true` — and only if Remote Control is on — the parent emits explicit notification language in its normal terminal output. For example:

> Notification sent. Tests passed (142 green, 0 failed) — user should be notified on Slack and via mobile push.

The exact wording doesn't matter; what matters is that the moment is unambiguously a user-notification event in the parent transcript. Anthropic's mobile push system is **not a tool** — there's no `push_to_mobile()` call. It's an automatic classifier that fires when (a) Remote Control is active and (b) Claude reaches a moment that warrants user attention.

If Remote Control is off, mobile push cannot fire — Anthropic's push system requires an active Remote Control session as the addressing mechanism. In that case, only Slack goes out, and the parent's terminal output should note: `Mobile push skipped — no active Remote Control session.`

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
