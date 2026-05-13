---
name: handle-feedbacks
description: Manually-invoked feedback triage. Invoke explicitly via `/handle-feedbacks` (or when the user says "triage these feedbacks", "handle this feedback batch", "process my review notes"). Spawns parallel triage agents that classify each feedback as question / correction / plan, walks the user through questions then corrections one-by-one, runs background planning agents so the user is never blocked, and emits a paste-ready 1-liner for a fresh Claude instance to execute the plans. Do NOT auto-trigger on routine code edits or generic feedback discussions — only fire on explicit user invocation.
---

# handle-feedbacks — feedback triage orchestrator

You are running a structured triage flow over a batch of feedbacks the user gave you about a target codebase. Your job is **orchestration**: spawn parallel triage agents, walk the user through results one-by-one, kick off background planning agents on resolution, and hand off a clean execution prompt for a fresh Claude session.

**Do not implement the feedbacks yourself.** This skill produces plan files. Implementation happens in a separate Claude session via the handoff 1-liner you emit at the end.

---

## 1. Capture inputs

You need two things:

1. **Target codebase root.** Default to the current working directory's git root:

   ```bash
   git rev-parse --show-toplevel 2>/dev/null || pwd
   ```

   If the user explicitly named a different path in their invocation, use that instead.

2. **The feedback list.** Accept any of:
   - Inline text in the invocation message (most common — paste of bullet points / numbered list)
   - One or more file paths to feedback documents
   - A mix of both

   If neither was provided, ask exactly once: *"What feedbacks should I triage? Paste them here or give me file paths."*

If the batch contains fewer than 2 feedbacks, confirm with the user before proceeding — the parallel-triage flow has setup overhead that only pays off for batches.

---

## 2. Create the triage workspace

Generate a unique key from the current timestamp plus a 3-character random suffix:

```bash
KEY="$(date +%Y%m%d-%H%M%S)-$(openssl rand -hex 2 | head -c 3)"
```

Create the workspace inside the **target codebase root** (not cwd if they differ):

```
<target-root>/docs/feedbacks/triage/{KEY}/
  feedbacks/      # raw feedback inputs, one file per feedback
  questions/      # triage agent output: ambiguous feedbacks
  corrections/    # triage agent output: suspected user mistakes
  plans/          # final implementation plans
  resolved/       # corrections the user accepted as-is (audit trail)
  _state.md       # tracks pending background planning agents
```

Split the user's feedback list into one file per feedback. Naming: `NNN-<slug>.md` where:
- `NNN` is a zero-padded sequence number starting at `001`
- `<slug>` is a 3–5 word kebab-case slug derived from the first sentence

Each `feedbacks/NNN-<slug>.md` contains the raw feedback text verbatim — no editing.

Initialize `_state.md` as empty.

**Resume check.** Before creating a new key, look at `<target-root>/docs/feedbacks/triage/`. If an existing directory has a non-empty `_state.md` with un-DONE entries, ask the user: "Resume `<existing-key>` or start fresh?"

---

## 3. Phase 1 — parallel triage

For every `feedbacks/NNN-*.md`, spawn one Agent (`subagent_type: general-purpose`) **in parallel** — single message, multiple Agent tool calls. Cap at 5 concurrent; if there are more, run in waves of 5.

### Triage agent prompt template

```
You are triaging one item from a feedback batch on a target codebase. Decide which bucket it belongs in and write a single output file.

Target codebase root: <ABSOLUTE_TARGET_ROOT>
Workspace root:      <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/
Feedback file:       <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/feedbacks/NNN-slug.md

Read the feedback file. Read the relevant code in the target codebase to ground your judgment — search broadly if scope is unclear, but stay focused on this one feedback.

Pick exactly ONE bucket:

a) UNCLEAR — you can't act without an answer from the user.
   → write to: questions/NNN-slug.md

b) USER MISTAKE — the feedback contradicts the code or rests on a wrong premise, and you can point to specific evidence.
   → write to: corrections/NNN-slug.md

c) ACTIONABLE — feedback is clear and you can produce a usable plan now.
   → write to: plans/NNN-slug.md
   → Read ~/.claude/skills/spec-writer/SKILL.md and produce the plan using its 13-section task-packet structure. **Skip spec-writer's pre-spec interview** — you are an agent with no user to ask; mark any genuine gaps as `<INPUT_REQUIRED>` in §5 (Open Questions). **Ignore spec-writer's sprint-folder filename convention** — the filename and location are fixed: `plans/NNN-slug.md` inside this workspace, and the H1 should be `# Plan: <one-line summary>` with a `**Source feedback:** feedbacks/NNN-slug.md` line below it.
   → For code changes, also read ~/.claude/skills/clean-code/SKILL.md and apply its principles within the spec's Approach / Implementation sections.

Rules:
- Write to exactly ONE bucket. Do not split a feedback across multiple files.
- Do not modify any other file in the workspace or target codebase.
- File templates for questions/ and corrections/ are below — follow them. For plans/, follow spec-writer's structure (see above).

[questions/NNN-slug.md template]
# Question: <one-line summary>

**Source feedback:** feedbacks/NNN-slug.md

**Why this is unclear:**
<2-3 sentences>

**What I need to know:**
- <specific question 1>
- <specific question 2>

**Relevant code:**
- path/to/file.ext:LINE — <one-line context>


[corrections/NNN-slug.md template]
# Possible correction: <one-line summary>

**Source feedback:** feedbacks/NNN-slug.md

**What the feedback says:**
<quote or close paraphrase>

**What I see in the code:**
<evidence with file:line refs>

**Why I think the feedback may be wrong:**
<reasoning>

**Confidence:** low | medium | high
```

After all triage agents return, verify each one wrote exactly one output file in the expected bucket. If an agent failed or wrote junk, treat that feedback as a question and write a minimal `questions/NNN-slug.md` yourself describing the failure.

---

## 4. Show summary

Print a compact summary the user can scan:

```
Triage workspace: <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/

  questions/   N items
    - 001-foo
    - 003-bar
  corrections/ M items
    - 002-baz
  plans/       P items (already actionable)
    - 004-qux

Walking through questions first, then corrections.
```

---

## 5. Walkthrough — questions (one by one)

For each file in `questions/`, in numerical order:

1. `Read` the file.
2. Present it to the user in a digestible format — do not dump the raw markdown. Summarize:
   - The original feedback (1 line)
   - Why the triage agent flagged it (1-2 sentences)
   - The specific ask
   - Code references if useful
3. Ask the user for an answer. Use `AskUserQuestion` when there are 2–4 clear choices; otherwise free-form.
4. Based on the user's answer, classify:
   - **→ correction**: the answer reveals the feedback was based on a wrong premise. `mv` the file from `questions/` to `corrections/` (preserving the filename), then continue to the next question.
   - **→ plan**: the answer makes the feedback actionable. Spawn a **background planning agent** (see template below) and append a `PENDING: NNN-slug.md` line to `_state.md`. Move on to the next question immediately — do NOT wait for the agent.

### Background planning agent template

Spawn with `run_in_background: true`, `subagent_type: general-purpose`:

```
Produce a final plan file for a triaged feedback.

Target codebase root: <ABSOLUTE_TARGET_ROOT>
Workspace root:      <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/
Feedback file:       <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/feedbacks/NNN-slug.md

Original triage output (question or correction):
<inline contents of the questions/NNN-slug.md or corrections/NNN-slug.md file>

User's resolution:
<inline text of the user's answer / decision>

Read ~/.claude/skills/spec-writer/SKILL.md and produce the plan using its 13-section task-packet structure (grounded citations, manual QA tables, the works). The user's resolution above is your interview input — **skip spec-writer's pre-spec interview**; mark any remaining gaps as `<INPUT_REQUIRED>` in §5 (Open Questions). For code changes, also read ~/.claude/skills/clean-code/SKILL.md and apply its principles inside the Approach / Implementation sections.

**Ignore spec-writer's sprint-folder filename convention.** The plan file location is fixed:
  <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/plans/NNN-slug.md

Start the file with:

# Plan: <one-line summary>
**Source feedback:** feedbacks/NNN-slug.md

…then the 13 sections from spec-writer.

After writing the plan, append exactly this line to <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/_state.md:
DONE: NNN-slug.md
```

---

## 6. Walkthrough — corrections (one by one)

After `questions/` is empty, loop over every file in `corrections/` (which now includes both originals and any moved from questions):

1. `Read` the file.
2. Present in digestible format: what the feedback said, what the code shows, why the agent suspects a mistake, the agent's confidence.
3. Use `AskUserQuestion` with two options:
   - **Accept correction** — user agrees they were wrong. `mv` the file to `resolved/`.
   - **Convert to plan** — user disagrees and wants implementation anyway. Spawn the same background planning agent (template above), append `PENDING: NNN-slug.md` to `_state.md`, move on.

---

## 7. Wait for pending plans

Once `questions/` is empty AND every file in `corrections/` is either in `resolved/` or has a corresponding `PENDING:` entry, you need to wait for all background planning agents to finish before emitting the handoff.

Strategy:
- You'll receive notifications as background agents complete (the runtime delivers them automatically — do not poll or sleep).
- After each completion, check `_state.md` for any `PENDING:` lines that don't yet have a matching `DONE:`. When all pending lines are matched, proceed to step 8.
- If a background agent fails, surface the error to the user and ask: retry / skip / write a manual plan.

---

## 8. Emit the handoff 1-liner

When all plans are written, print the final block. The 1-liner must use **absolute paths** so the user can paste it into any fresh Claude session:

```
Triage complete. Plans ready in <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/plans/

Paste this into a fresh Claude instance:
─────────────────────────────────────────────────────────────────────
Implement the plans in <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/plans/.
Read each plan, work through them in parallel where file overlaps allow (group plans
that touch the same file into one sequential batch to avoid conflicts). After each
plan: run the verification step it specifies. When ALL plans are implemented and
verified, ask me to confirm — then delete <ABSOLUTE_TARGET_ROOT>/docs/feedbacks/triage/{KEY}/.
─────────────────────────────────────────────────────────────────────
```

End your turn after this message. Your job is done.

---

## Constraints and edge cases

- **Manually invoked only.** The frontmatter description suppresses auto-load. Do not invoke this skill on your own.
- **Skill does NOT delete the workspace.** Cleanup is the implementing session's responsibility, gated on user confirmation after verification. The handoff 1-liner makes that explicit.
- **Skill does NOT chain into prod-safety-gate / clean-code / vibesec at its own level.** It's pure orchestration. Plan-writing agents (both the Phase 1 triage agent on bucket `c` and the Phase 2 background planning agent) pull in `spec-writer` for the 13-section structure, and additionally pull in `clean-code` for code-bearing plans. The pre-spec interview from spec-writer is intentionally skipped — by the time a plan is being written, either the feedback was already actionable (Phase 1) or the user's resolution has already been captured (Phase 2).
- **Skill does NOT auto-implement plans.** The handoff is the exit point — do not start implementing.
- **Single batch at a time.** If a previous in-progress key exists in `docs/feedbacks/triage/`, ask the user whether to resume or start fresh.
- **Don't block the user during planning.** Plan generation is always a background agent so the user can move to the next question / correction immediately.
- **Trust but verify the triage agents.** After Phase 1, confirm each expected output exists and is in the right bucket. Recover gracefully when one misbehaves.
- **No nested triage.** If a feedback is itself "the previous triage was wrong", treat it as a normal feedback — do not recursively spawn another `handle-feedbacks` flow.
