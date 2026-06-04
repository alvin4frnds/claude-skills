---
name: bug-quash
description: Manually-invoked single-bug lifecycle. Invoke as `/bug-quash [number] <description>` (or when the user hands you a bug — text and/or a pasted screenshot — and says "quash it", "fix this bug", "squash bug N"). The number is optional; if omitted, auto-assign the next integer from the running session bug count (BUG-1, BUG-2, …). A pasted/attached image is a first-class input — read its error text/screen and use it as the expected-vs-actual reference. Drives ONE bug through a fixed pipeline — understand → reproduce → analyse → RCA → clarifying questions → fix (in a git worktree when non-trivial) → test the fix end-to-end (UI via Chrome or API via curl, whichever the bug calls for) → verify → merge to LOCAL master (never push) → remove the worktree → summarise. The bug label is session-only (BUG-<n>); no persistent tracker is created. Runs only the related/targeted tests, never the full suite, using the test command discovered from package.json / composer.json / Makefile / pyproject. Chains clean-code → vibesec on the fix.
---

# bug-quash — drive one bug from report to verified fix

You take a single bug and walk it through a fixed lifecycle, one stage at a
time, stopping at the gates. You do **not** batch bugs, you do **not** push,
and you do **not** skip reproduce or verify. The whole point is that a bug is
only "quashed" when you have **watched it fail, watched the same path pass after
your change, and merged that change to master** — anything less gets reported
honestly, not dressed up as done.

## Invocation, the session label & inputs

Invoked as `/bug-quash [number] <description>` — the number is **optional**:

- `/bug-quash 412 logout button does nothing on Safari` → use `412`.
- `/bug-quash logout button does nothing on Safari` (no number) → **auto-assign
  from the running session bug count.** Track how many bugs you've taken this
  session and give this one the next integer: first bug → `BUG-1`, second →
  `BUG-2`, and so on. State the number you assigned in the first line of your
  reply (e.g. "Taking this as **BUG-3** (3rd bug this session)."). If the user
  later supplies a real tracker number, switch to it and say so.

`BUG-<n>` is a **session-only tracking label**. Use it in branch names, worktree
names, commit messages, task titles, and every section header below. Do **not**
create or update any external/persistent bug tracker, file, or database — the
label and the session counter live and die with this session.

**Inputs can include a pasted/attached image.** A screenshot is often the whole
bug report (a broken UI, a stack trace, a console error, a wrong number on a
dashboard). When the user pastes or attaches an image:

- Read it as a first-class part of the bug description in §1 — transcribe the
  visible error text, identify the screen/component, note any URL/element shown.
- Treat the screenshot as the **expected-vs-actual reference** for §2 Reproduce
  and §7 Test: your job is to make the real UI/output stop matching the broken
  screenshot. If the image shows a stack trace or error string, grep the
  codebase for that exact text to jump straight to the source.
- If the description is image-only with no words, infer the symptom from the
  image and confirm your reading back to the user before fixing.

Track the lifecycle stages with the session task list (TaskCreate one task per
stage, or a single task you check off) so the user can see where the bug is.
This is the only "tracking" — it is ephemeral.

## Companion skills (chained on the fix)

When you reach **§6 Fix**, before writing the change load and apply:

1. `~/.claude/skills/clean-code/SKILL.md` — readability discipline on the fix.
2. `~/.claude/skills/vibesec/SKILL.md` — security review of the change.
   (`clean-code` auto-loads this; reading it will surface the directive — honor it.)

For a **high-risk** fix (auth, authorization, payments, money/points/ledgers,
migrations, data deletion, background jobs, webhooks, secrets, infra), also
recommend the user run `/prod-safety-gate` first — it is manual-invoke only, so
do not auto-load it, but say plainly when a bug is in its territory.

Order of precedence on conflict: **vibesec (security) > bug-quash (process) > clean-code (style)**.

---

## The pipeline (do not reorder, do not skip a gate)

```text
1 Understand → 2 Reproduce → 3 Analyse → 4 RCA → 5 Questions (if any)
  → 6 Fix (worktree if non-trivial) → 7 Test the fix → 8 Verify
  → 9 Merge to local master → 10 Remove worktree → 11 Summarise
```

Two hard gates:
- **Reproduce gate (§2):** do not start analysing a fix path until you have
  either reproduced the bug or explicitly declared it not-reproducible and
  agreed a path forward with the user.
- **Verify gate (§8):** do not merge until the fix is verified against the
  original reproduction and the targeted tests are green.

---

## 1. Understand

Restate the bug as a contract before touching anything.

```md
## BUG-<n> — Understanding
- Reported symptom: <what the user sees>
- Screenshot says: <transcribed error text / screen / element — omit if no image>
- Expected behaviour: <what should happen instead>
- Surface: <UI page / API endpoint / job / CLI — where it lives>
- Trigger / repro hint: <steps, payload, account, or env the reporter gave>
- Severity / blast radius: <who/what is affected>
- Unknowns: <what you still need to find out>
```

Inspect the relevant code **before** theorising (read-before-write): the module
that owns the surface, its tests, related logging, and recent git history for
that area (`git log --oneline -- <path>`) — a recent commit is often the cause.

## 2. Reproduce

Reproduce the failure **first**, by the cheapest faithful means:

- **API / backend bug** → reproduce with `curl`, a test harness call, a
  `psql`/db query, a one-off script, or a failing unit test that exercises the
  real path. Capture the actual wrong output.
- **UI / frontend bug** → reproduce in the browser. Load the Chrome tools via
  `ToolSearch` (`select:mcp__claude-in-chrome__tabs_context_mcp`, `...navigate`,
  `...read_page`, `...computer`, `...read_console_messages`,
  `...read_network_requests`), open a **new** tab, drive the failing flow, and
  capture the console error / network failure / wrong rendering. Consider a
  short GIF (`gif_creator`) when the repro is motion-dependent.
- **Data / job / cron bug** → reproduce by running the job or querying the data
  in a safe (non-production) context.

Record it:

```md
## BUG-<n> — Reproduction
- How I reproduced: <command / steps / URL>
- Observed (wrong) result: <paste actual output / error / screenshot note>
- Matches the report? yes / partially (explain) / no
```

If you **cannot** reproduce: do not guess at a fix. State what you tried, ask
for the missing piece (account, payload, env, exact steps), and stop at this
gate.

## 3. Analyse

Trace the failing path from the reproduction down to the code. Narrow from
symptom → component → function → line. Use logs, stack traces, network panel,
`git blame`, and targeted reading. Form a hypothesis and **confirm it against
the code/runtime**, don't assert it. Distinguish the **symptom** from the
**defect**.

## 4. RCA (root cause analysis)

State the actual root cause — the defect, not the symptom — and why it produces
the observed failure.

```md
## BUG-<n> — Root cause
- Root cause: <the precise defect, at file:line>
- Why it manifests as the reported symptom: <causal chain>
- Why it wasn't caught: <missing test / edge case / assumption>
- Blast radius: <other call sites / data already affected by this bug>
- Fix strategy (smallest safe change): <what you intend to change and why>
```

If "data already affected" is non-empty, flag whether a backfill/cleanup is
needed — that may be a separate follow-up, surface it.

## 5. Questions (if any)

If the root cause exposes an **ambiguity in intended behaviour** — not a code
question you can answer by reading, but a product/business decision — stop and
ask via `AskUserQuestion` before fixing. Use the pattern:

```md
Ambiguity affecting the fix:
- Question: <what's unclear>
- Why it matters: <what changes depending on the answer>
- Safe default: <what I'll do if you don't override>
```

If there are no genuine ambiguities, say so in one line and move on. Do **not**
invent business logic.

## 6. Fix

### 6a. Decide on isolation (worktree only if non-trivial)

Judge the change first:

- **Trivial** (a one-/few-line change in a single file, no migration, no
  cross-module impact, no high-risk area) → fix **in place on a `fix/bug-<n>-<slug>`
  branch** off master. Don't pay the worktree cost.
- **Non-trivial** (multiple files, migrations, high-risk area per the companion
  chain, or anything you'd want isolated) → use a **git worktree**.

Either way, **never work directly on master/main/develop/release branches** —
create the fix branch first. Check the branch before editing.

For the worktree path, follow `~/.claude/skills/using-git-worktrees/SKILL.md`
for directory selection (prefer an existing `.worktrees/`, verify it is
git-ignored). Typical setup:

```bash
git worktree add .worktrees/bug-<n> -b fix/bug-<n>-<slug> master
```

Do all fix work inside that worktree. **Never touch worktrees you didn't
create** (other sessions may have parallel ones).

### 6b. Make the change

Apply the **smallest safe change** that addresses the root cause from §4 — not
the symptom, not an opportunistic refactor. Now apply the companion chain
(clean-code → vibesec) to the change. If the bug is a regression, prefer adding
or fixing the test that should have caught it.

## 7. Test the fix (end-to-end, bug-dependent)

First re-run the **original reproduction from §2** against the fixed code — the
exact same command / UI flow / query — and confirm the wrong result is now the
right result. Reproduction-passing is the primary evidence; tests back it up.

- **API bug** → re-run the `curl`/script/query; confirm the corrected response.
- **UI bug** → re-drive the flow in Chrome; confirm the error is gone and the
  console/network are clean.
- **Job/data bug** → re-run the job; confirm correct output.

### Targeted tests only — never the full suite

Discover the project's test command, then run it **scoped to the changed
files/area only**:

1. Find the runner:
   - `package.json` → `scripts.test` (and friends like `test:unit`); run via
     `npm test`/`pnpm test`/`yarn test`. Scope with the test file path or a
     name filter (e.g. `npm test -- path/to/file.test.ts`, `vitest run <file>`,
     `jest <pattern>`).
   - `composer.json` → `scripts.test`; run e.g. `composer test -- --filter
     <TestName>` or the underlying `./vendor/bin/pest <path>` / `phpunit
     --filter`.
   - `Makefile` → a `test` target (`make test`); look for a narrower target if
     one exists.
   - `pyproject.toml` / `setup.cfg` → `pytest <path::test>`.
   - else inspect CI config for the canonical command.
2. Run **only** the tests covering the touched files (the new/updated test, the
   module's existing tests). Do **not** run the whole suite for one bug — it's
   slow and out of scope. If you genuinely can't scope it, say so and run the
   narrowest thing available.

```md
## BUG-<n> — Fix test
- Repro re-run: <command> → now returns <correct result> ✅
- Test command (discovered from <file>): <exact scoped command>
- Result: <pass/fail, counts>
```

If the repro still fails or tests fail, go back to §3 — do not proceed.

## 8. Verify (gate)

Independently confirm the fix is real and clean before merging:

```md
## BUG-<n> — Verification
- Original symptom reproduced before fix? yes
- Same path passes after fix? yes (evidence: <ref>)
- Targeted tests green? yes (<command>)
- Diff reviewed (`git diff`): no debug logs / stray prints / secrets / unrelated churn
- No new regressions in the touched module
- Risk / follow-ups: <backfill needed? related call sites? feature flag?>
```

Only when every line above holds do you proceed to merge.

## 9. Merge to local master (NEVER push)

Merge the fix branch into **local** `master`. **Do not `git push`** — the user
reserves all pushes. Report the SHA.

```bash
git -C <repo-root> checkout master
git -C <repo-root> merge --no-ff fix/bug-<n>-<slug> -m "fix: BUG-<n> <short description>"
git -C <repo-root> rev-parse HEAD   # report this SHA
```

End commit messages with the standard co-author trailer if the repo convention
expects it. If the merge conflicts, resolve in the worktree/branch (rebase onto
current master), re-verify §7–§8, then merge — never force a dirty merge.

## 10. Remove the worktree

Only if you created one in §6a:

```bash
git worktree remove .worktrees/bug-<n>      # add --force only if you're sure it's yours & clean
git branch -d fix/bug-<n>-<slug>            # branch is merged; -d is safe
```

Never remove a worktree or branch you didn't create.

## 11. Summarise

Close with a tight report:

```md
## BUG-<n> — Quashed ✅
- **Symptom:** <one line>
- **Root cause:** <one line, file:line>
- **Fix:** <what changed, files>
- **Evidence:** repro re-run + <scoped test command> green
- **Merged:** master @ <SHA> (not pushed)
- **Worktree:** removed (or: fixed in place on branch <name>)
- **Follow-ups / risks:** <backfill, related bugs, flags — or "none">
```

Never write "Quashed" if reproduction wasn't confirmed both ways, tests were
skipped/failed, or the merge didn't happen — report the real state instead and
say what's blocking.

---

## Operating rules (override convenience)

- **One bug at a time.** This skill is single-bug. If handed several, do them
  sequentially, each through the full pipeline.
- **Never push.** Merge to local master only; surface the SHA; the user pushes.
- **Never run the full test suite for a bug** — targeted tests only (§7).
- **Reproduce before fixing, verify before merging** — the two hard gates.
- **Smallest safe change** — fix the root cause, resist bundling refactors.
- **Honest status** — a bug you couldn't reproduce or fully verify is not
  quashed; say so.
