---
name: recommend-skills
description: Explicitly invoked meta-skill. When the user runs `/recommend-skills <task prompt>` (or otherwise tells you to use the recommend-skills meta-skill), match that task against the local awesome-claude-skills catalog, let the user pick skill(s) via AskUserQuestion, then handle the original task using the selected skill(s) — in the same turn, without asking the user to retype the prompt.
---

# recommend-skills — meta-skill

This skill is invoked **explicitly** by the user. Its job is to (1) find the best skill(s) from a local catalog for the user's current task, (2) let the user pick which to apply, and (3) carry out the user's original task using the chosen skill(s) — all in one turn.

## Catalog location

`/Users/praveen/Desktop/code/learning/claude-skills`

Each subdirectory that is a skill contains a `SKILL.md` whose YAML frontmatter has `name:` and `description:` fields.

## Procedure

Follow these steps in order. Do not skip steps. Do not ask the user to re-state their task.

### 1. Capture the user's original task prompt

The "task prompt" is whatever the user wrote alongside the invocation. Example:

- User typed: `/recommend-skills draft a tailored resume for a staff engineer role at Stripe`
- Task prompt = `draft a tailored resume for a staff engineer role at Stripe`

If the user invoked the skill with **no task prompt** (empty args), ask them once: "What task should I match against the skills catalog?" — then proceed.

### 2. Scan the catalog frontmatter

Run this Bash command to pull frontmatter from every skill in one call:

```bash
for f in /Users/praveen/Desktop/code/learning/claude-skills/*/SKILL.md; do
  echo "=== $f ==="
  head -10 "$f"
done
```

If the catalog directory is missing, tell the user the expected path and stop.

If you suspect skills nested one level deeper (e.g. plugin bundles), also check `/Users/praveen/Desktop/code/learning/claude-skills/*/*/SKILL.md` with a follow-up glob.

### 3. Rank by semantic relevance

Read the captured `name` and `description` of each skill and pick the **top 3 candidates** most relevant to the task prompt. Judgement criteria:

- Direct topical match (e.g. task mentions "resume" → `tailored-resume-generator`).
- Procedural match (e.g. task says "test my web app" → `webapp-testing`).
- Stackable enhancers (e.g. design tasks may benefit from `brand-guidelines` + a primary skill).

If nothing looks like a strong match, still surface the 3 closest — the user decides.

### 4. Present the picker

Call `AskUserQuestion` with exactly one question:

- `question`: a short phrasing like "Which skill(s) should I apply to your task?"
- `header`: `"Pick skills"` (≤ 12 chars)
- `multiSelect`: `true`
- `options`: up to 4 entries:
  - First 3 options = your top-ranked skills. `label` = skill name (≤ 5 words). `description` = one-line rationale explaining why it fits this task.
  - 4th option: `label`: "None — proceed anyway", `description`: "Handle the task without applying any catalog skill."

### 5. Load the selected skill(s)

For each skill the user picked (skip this step if they picked "None"):

1. `Read` the full `SKILL.md` of that skill directory.
2. If the SKILL.md references helper files (`scripts/`, `templates/`, `resources/`, etc.) **and** those helpers are needed for the current task, read only the ones that are needed.

If multiple skills were selected, treat their instructions as additive — apply all of them. If two skills conflict, prefer whichever one is more task-specific and note the conflict briefly to the user.

### 6. Execute the original task

Now handle the user's **original task prompt** (captured in step 1) as if the selected skill(s) had been loaded from the start. Do not ask the user to restate the task. Do not summarize what you are about to do — just do it, following the selected skill's instructions.

If the user picked "None", handle the task prompt with your default behavior.

## Constraints and edge cases

- **Never invoke this skill on your own.** It only runs when the user explicitly asks for it.
- **Don't re-ask for the task.** The user does not want to retype.
- **Stay in one turn.** Steps 1–6 all happen within the same assistant response cycle (the AskUserQuestion pause is not a new turn from the user's perspective).
- **AskUserQuestion caps options at 4.** Keep the shortlist to 3 skills + "None".
- **Labels ≤ 5 words.** Long skill names (e.g. `tailored-resume-generator`) are fine as-is; put the rationale in `description`.
- **Catalog missing or empty** → tell the user the expected path, do not invent skills.
