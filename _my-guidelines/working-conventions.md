# Working conventions (Praveen)

These are standing rules for how I want you to work. They apply in every project
and on every machine. Follow them proactively — infer intent, don't wait to be
told each time.

## Skills first — never freehand what a skill exists for

Before doing a task from memory, check your available-skills list. If a skill
covers it, **invoke the skill** — do not reproduce its job by hand. In particular:

- "spec" / "scope this" / "spec this out" / "task packet" / "write a spec"
  → invoke **spec-writer**. Never hand-write a spec from memory.
- "triage these feedbacks" / feedback batch → **handle-feedbacks**.
- security review / audit / "is this safe" on web code → **vibesec**.
- refactor / "clean this up" / readability → **clean-code**.

If you're unsure whether a skill applies, prefer trying the skill over freehanding.

## Notifying me → always Slack via the skill

Any phrasing that means "tell me when this is done / ready / finished" —
"let me know", "ping me", "notify me", "slack me", "give me a shout",
"tell me when" — **invoke the `slack-notify` skill**. That's the only way I
actually get the push. Don't just print "done" in the terminal and stop.

## Sending me a file / diagram → Dropbox relay, never a direct upload

"slack me this file", "send me this", "share this diagram/screenshot/chart"
→ invoke the **share-diagram** skill (it runs `~/.claude/bin/send-diagram-slack.sh`:
Dropbox upload → public link → inline Slack post as the @Claude bot).

**Never** attempt a direct Slack file upload via an MCP Slack tool — the bot has
no `files:write` scope, so a direct upload just fails silently. Always go through
the Dropbox relay.

## Blockers → Slack me immediately, unprompted

If you hit a real blocker — something where you genuinely can't make progress
without me — **proactively invoke `slack-notify` right away**, without being asked.
Infer this; I should not have to say "ping me if you get stuck" each time.

A blocker means, for example:
- missing/invalid credentials, tokens, or access you can't obtain yourself
- a hard prerequisite gate that fails (e.g. IMPLEMENTATION_PLAN §6 unfilled)
- an ambiguous requirement where every path forward risks being wrong work
- a destructive / irreversible / outward-facing action that needs my sign-off
- a failing external dependency (CI, deploy, remote service) with no workaround

Not a blocker: a normal decision you can make with a sensible default, or a test
you can just fix. Use judgment — don't Slack me for trivia, do Slack me the moment
you'd otherwise sit idle waiting on me.

## Slack mechanics

Slack sends go to my Xure DM via the @Claude bot token (the `slack-notify` /
`share-diagram` skills handle this). Never use the `claude_ai_Slack` connector
(wrong workspace).
