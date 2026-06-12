---
name: implement-sprint
description: Autonomously implement an entire sprint's task packets one-by-one via isolated git-worktree agents, merging each green packet back to the branch HEAD is on (`dev` or `master`, not always `master`). Invoke via `/implement-sprint` (optionally `/implement-sprint 15` to pin a sprint). Picks the latest `docs/todos/sprint N/` by default, walks every `claude-task--NNN--*.md` in order, SKIPS any packet already marked Done without re-verifying, and for the rest spawns one worktree agent that verifies-if-already-done → implements → drives the full toolchain + every BE/FE/CHROME manual-QA case green → flips Status to Done. The orchestrator then merges that worktree back to the integration branch and moves on; if HEAD is on neither `dev` nor `master`, it stops and tells the operator. Never pushes (operator reserves pushes); never touches foreign worktrees/changes from parallel agents.
---

# implement-sprint — autonomous per-packet sprint executor

You are the **orchestrator** for shipping a whole sprint. You do not write the
feature code yourself — you enumerate the sprint's packets, decide per packet
whether work is even needed, dispatch one **isolated git-worktree agent** per
packet that does the implementation + the entire QA gate, then **merge each
green packet into the integration branch** — the branch HEAD is on, `dev` or
`master`, **not always `master`** (§1a) — before moving to the next. One packet
at a time, in numeric order.

This skill exists because the repo has a hard **Stop hook**
(`.claude/hooks/qa-test-gate.sh`) that blocks stopping while any of the
packet's §12b manual-QA cases are left un-run. The hook reads the packet's
§12b **Status column on disk** (not the chat), and — after the s14t29
post-mortem — it distinguishes **LIVE rows** (steps that hit a real
round-trip: `curl` / `psql` / `php artisan migrate|tinker` / Playwright /
`/horizon` / `FB GET` / a real platform call) from **SHAPE rows** (payload
structure only). A LIVE row is satisfied **only by a real run** — a green
Pest with a mocked SDK / `FacebookCallExecutor` does **not** count, because it
never calls the platform (that is precisely how s14t29's `asset_feed_spec` →
FB `(#3)` shipped green and reached a customer). The whole BE + FE + CHROME
gate is the agent's responsibility — not the operator's, not a follow-up.

---

## 0. Operating rules (read these first — they override convenience)

- **Never `git push`.** The operator reserves all pushes (memory:
  `never-push`). You commit and merge to the local **integration branch** (the
  `dev` or `master` branch HEAD is on — §1a) only, and report SHAs.
- **Never touch foreign work.** Other Claude sessions run parallel worktree
  agents (`.claude/worktrees/agent-*`, often `locked`). Do not read, rebase,
  merge, or `git worktree remove` any worktree you didn't create. When merging,
  only your packet's own files move. If `git status` on the integration branch
  shows changes you didn't make, leave them — they belong to another agent or
  the operator.
- **One packet at a time, numeric order.** `001`, then `002`, … Do not
  parallelise packets — later packets in a sprint often build on earlier ones,
  and serialising keeps the merge to the integration branch clean.
- **Skip Done packets with zero verification.** If a packet's `**Status:**` line
  reads `Done` / `Complete` / `Shipped` / `Merged`, log it and move on. Do not
  re-open, re-verify, or re-run its tests. (This is the operator's explicit
  rule: trust the Done marker.)
- **Verify-before-build for everything else.** A `Draft`/`In Progress` packet
  may already be implemented (its §12b matrix may already cite green tests).
  The agent's *first* substantive job is to check whether the change is already
  present and passing — if so, it flips Status to Done and returns "already
  done" without editing code.
- **Slack only at sprint close or on a hard blocker** (memory:
  `sprint-after-sprint`). Don't ping between packets.

---

## 1. Resolve the integration branch, the sprint, and enumerate packets

### 1a. Resolve the integration branch (do this FIRST, before any dispatch)

Every green packet merges back into **whatever branch HEAD is on** — `dev` or
`master`, **not always `master`**. Capture it once and thread it through the
whole run (the agents' rebase base, the merge target, the post-merge gate, and
close-out):

```bash
BASE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
echo "integration branch = $BASE_BRANCH"
```

- `BASE_BRANCH` is `dev` or `master` → that **is** the integration branch. Stay
  checked out on it for the entire run; every `git merge --no-ff <agent-branch>`
  (§2c) lands here, and every agent rebases onto it (§2b STEP 1).
- `BASE_BRANCH` is **anything else** — a feature branch, or detached `HEAD`
  (the command prints `HEAD`) → **STOP. Do not enumerate, do not dispatch any
  agent.** Tell the operator verbatim:
  > implement-sprint expects HEAD on `dev` or `master` so it knows where to
  > merge each green packet — but HEAD is on `<BASE_BRANCH>`. Check out the
  > branch you want this sprint merged into (`git checkout dev` or
  > `git checkout master`), then re-run `/implement-sprint`.

  This is a hard gate: silently picking a branch would land a sprint's worth of
  commits in the wrong place.

### 1b. Resolve the sprint and enumerate packets

```bash
# Pin via arg ("/implement-sprint 15") or default to the highest-numbered sprint.
ls -1 docs/todos/ | grep -E '^sprint [0-9]+$' | sort -t' ' -k2 -n | tail -1
ls -1 "docs/todos/sprint N/" | grep -E '^claude-task--[0-9]+--.*\.md$' | sort
```

Build the ordered worklist. For each packet, read its `**Status:**` line:

```bash
grep -m1 -oE '\*\*Status:\*\*[^|]*' "docs/todos/sprint N/claude-task--NNN--*.md"
```

- `Done`/`Complete`/`Shipped`/`Merged` → **SKIP** (record, no verification).
- anything else → **process** (§2).

Print the plan (packet → action) before starting so the operator can see the
shape. Use TaskCreate to track one task per processed packet if helpful.

---

## 2. Per-packet loop

For each packet to process, in order:

### 2a. Pick the model for the agent
Per memory `model-choice-per-packet`:
- **sonnet** for thin/derivative packets (report adapters, DB models, simple
  controllers, copy/disclosure/text polish, pure mockup-parity CSS).
- **opus** for SDK wiring, crypto/KVM, multi-step front-end, sync/distribution
  mapper logic, anything cross-domain.
Read the packet's §2 Objective + §9 file list to judge.

### 2b. Dispatch the worktree agent
Spawn **one** agent with `isolation: "worktree"` and the model from 2a. The
agent prompt MUST contain the literal packet path and these instructions
(adapt only the packet-specific bits):

> **STEP 1 — rebase onto the integration branch (`<BASE_BRANCH>`).** You are in
> a fresh worktree that may lag the integration branch (memory:
> `worktree-stale-base`) — the orchestrator substitutes the literal branch name
> (`dev` or `master`) for `<BASE_BRANCH>` below. `git fetch` is unnecessary
> (local), but run `git rebase <BASE_BRANCH>` (or `git merge <BASE_BRANCH>`)
> onto the current local `<BASE_BRANCH>` as your very first action, before
> reading or editing anything. Do **not** assume `master` — earlier packets in
> this sprint were merged into `<BASE_BRANCH>`, so that is the only base that
> carries their work.
>
> **STEP 2 — read the contract.** Read `CLAUDE.md`, `docs/CONVENTIONS.md`
> end-to-end (HARD gate, Part 1 workflow + Part 2 conventions + Part 4 page
> checklist), and the packet `docs/todos/sprint N/claude-task--NNN--*.md`
> end-to-end. Grep `docs/feedbacks/triage/` for the surface you're touching.
>
> **STEP 3 — VERIFY-FIRST: is this already done?** Before writing any code,
> check whether the packet's behavior already exists and passes. Concretely:
> open every NEW/changed file the packet's §9 names — do they already exist
> with the described behavior? Run the packet's §12a targeted verification
> (the cited Pest filter + Vitest specs). If the feature is fully present and
> those tests are green, DO NOT edit code — **but green Pest alone is not
> "done" for a packet that has LIVE §12b rows** (Steps that hit a real
> platform / DB / browser round-trip). Before flipping Status, you must still
> execute those LIVE rows for real per STEP 6 and record their true outcome; a
> mocked-SDK Pest cannot stand in for them (s14t29 lesson). Once §12a is green
> AND every LIVE §12b row reflects a real run, flip the packet's `**Status:**`
> to `Done`, append a one-line note under §12c citing what you ran, commit
> `docs(sprint N): mark NNN done — already implemented (<evidence>)`, and
> return a report saying "ALREADY DONE" with the evidence. Stop here.
>
> **STEP 4 — implement.** Otherwise implement strictly per §7 Acceptance
> Criteria + §9 Behavior Spec, honoring §8 Hard-NO list and all CONVENTIONS
> (folder discipline, no raw `DB::` under `app/Orchestrator/`, payload+mirror
> single transaction, approval gate, correlation-id, customer-string stop-list,
> `declare(strict_types=1)`, `final class`, domain-named exceptions). Only edit
> files this packet owns — do not reformat or "drive-by fix" unrelated files
> (a parallel agent may own them).
>
> **STEP 5 — GREEN GATE (all of it, from `code/backend/`).** This is mandatory
> and is yours alone — the Stop hook blocks on un-run QA:
> ```
> ./vendor/bin/pint --dirty
> ./vendor/bin/phpstan analyse --memory-limit=2G
> ./vendor/bin/deptrac analyse --no-progress
> ./vendor/bin/pest                 # full backend suite, real Postgres orchestrator_test
> npx vue-tsc --noEmit
> npx vitest run                    # full FE suite
> npm run build
> ```
> Plus the packet's §12a Hard-NO byte checks (each must print nothing).
>
> **STEP 6 — drive EVERY §12b manual-QA case to a truthful Status.** First
> classify each row by its **Steps**, because the substitution rules differ:
>
> - **LIVE row** — Steps hit a real round-trip (`curl` / `psql` /
>   `php artisan migrate|tinker` / Playwright / `/horizon` / `FB GET` / a real
>   Google/Facebook call / `act_<id>`). It MUST be run for real. **A green
>   Pest does NOT satisfy a LIVE row** — the test harness swaps platform SDK
>   clients via `App::instance` / mocks `FacebookCallExecutor`, so it asserts
>   the payload *we build* and can never surface a platform *rejection*
>   (s14t29 was 100% green Pest yet FB rejected the very payload with `(#3)`).
>   Run it against the real dependency: `php artisan tinker` on the dev
>   `orchestrator` DB, the live adapter against the real connected account, a
>   `tests/e2e/` Playwright spec (`APP_ENV=playwright`, server `:8001`, DB
>   `orchestrator_test`, seeded via `/__playwright/*`), or — for
>   reporting/metrics/scoring/sync — confirm the Horizon jobs finished with
>   **zero failures** at `/horizon` (memory `horizon-pass-mandatory`). Write
>   the **real outcome** into the Status cell: `Pass — <evidence>`, or the
>   actual failure verbatim (e.g. `Failed — FB (#3) on asset_feed_spec`). A
>   real failure is a legitimate, non-fakeable result — surface it, do not
>   paper over it.
> - **SHAPE row** — payload/structure only, no live token. A green Pest is
>   acceptable: set Status to `Verified via tests/Feature/<path>` citing the
>   real test file. Do **not** write the literal phrase `Not Run` even with a
>   "(covered by Pest)" suffix — the gate (rightly) treats `Not Run` as un-run.
>
> Use far-future dates (≥ 2027, memory `playwright-far-future-dates`) and the
> real Google + Facebook accounts (no `SIM_*`, memory `exercise-real-flow`).
> **Never leave a row `Not Run`/`Blocked`/`Skipped`/`Deferred`**, and **never
> relabel a LIVE row as "covered by Pest"** — both are exactly what the Stop
> hook rejects. Mark `Blocked` ONLY after a real attempt fails AND you name the
> exact operator-only blocker (which seed row / OAuth cred / migration).
>
> **STEP 7 — finish.** Tick §12c Definition of Done. Flip `**Status:**` to
> `Done`. Commit with a message referencing the packet's repo-root-absolute
> path (`docs/todos/sprint N/claude-task--NNN--*.md`). Do NOT `git push`. In
> your final message report: ALREADY-DONE vs IMPLEMENTED, the commit SHA(s) on
> your branch, the gate results (pest/vitest/build pass counts), and the §12b
> matrix final state. If you hit a genuine blocker you cannot clear, report it
> precisely and stop — do not fake a Pass.

### 2c. Merge the green packet to the integration branch (orchestrator does this)
When the agent returns success:
1. **Manager QA audit (do NOT just trust the agent's report).** Re-read the
   packet's `§12b` matrix **on disk** on the agent's branch and reject the
   merge if any of these hold — send the packet back to a fresh agent with the
   specific rows quoted:
   - any row Status is `Not Run` / `Blocked` (without a named operator-only
     blocker) / `Skipped` / `Deferred` / `N/A`;
   - any **LIVE row** (Steps hit `curl` / `psql` / `php artisan migrate|tinker`
     / Playwright / `/horizon` / `FB GET` / a real platform call) is satisfied
     only by a Pest/mock citation (`covered by`, `Verified via tests…`,
     `mocked`, `stubbed`) instead of a real-run outcome — a green Pest cannot
     clear a LIVE row (s14t29 lesson);
   - the packet `**Status:**` was flipped to `Done` while either of the above
     is true.
   This mirrors the Stop hook's logic; the hook guards the agent's session, the
   manager guards the merge. A LIVE row whose Status records a **real failure**
   (e.g. `Failed — FB (#3)`) does NOT block the audit — but it means the
   feature is not shippable: do not merge; surface it to the operator.
   Then spot-check the diff touches only this packet's files + its packet `.md`.
2. Merge the agent's worktree branch into the local **integration branch**
   (`$BASE_BRANCH` from §1a — `dev` or `master`). First confirm you're still on
   it (`git rev-parse --abbrev-ref HEAD` → `$BASE_BRANCH`), then:
   ```bash
   git merge --no-ff <agent-branch> -m "merge(sprint N): NNN <slug>"
   ```
   `git merge` lands the branch into whatever is checked out, so staying on
   `$BASE_BRANCH` is what makes this `dev`-aware — never `git checkout master`
   first. Resolve conflicts in favour of keeping **both** your packet and any
   foreign changes already on `$BASE_BRANCH` — never clobber another agent's work.
3. Re-run the fast gate on `$BASE_BRANCH` to catch merge drift
   (`./vendor/bin/pest --filter <packet surface>` + `npm run build`). The
   classic merge-time biters (memory `parallel-agent-lessons`): `phpstan.neon`,
   `AppServiceProvider`, `bootstrap.php`, `User.php`, `deptrac.yaml`,
   driver match-arms — eyeball these if the packet touched them.
4. **Clean up the merged worktree (mandatory).** Once the packet's commits are
   on `$BASE_BRANCH` and the fast gate passed, remove the agent's worktree and branch
   — stale worktrees carry full `vendor/` + `node_modules/` copies (~0.5 GB
   each) and once bloated `make dev-sync` into a ~278k-file rsync that looked
   hung:
   ```bash
   git worktree remove .claude/worktrees/<agent-worktree>   # --force if needed; it's merged
   git branch -d <agent-branch>
   git worktree prune
   ```
   Only ever remove worktrees/branches **you** created this session — foreign
   `agent-*` worktrees belong to parallel sessions (rule §0).
5. Report the `$BASE_BRANCH` SHA. Move to the next packet.

> If `isolation:"worktree"` agents can't merge cleanly because the harness
> auto-cleans the worktree, instead have the agent leave its branch in place
> and you `git merge` the branch name it reports; or cherry-pick its commits.
> Worktree auto-removal only happens if the worktree is unchanged — a committed
> packet is not.

---

## 3. Close-out

After the last packet:
- Print a sprint summary table: packet → ALREADY-DONE / IMPLEMENTED / BLOCKED,
  `$BASE_BRANCH` SHA, gate state. Name the integration branch in the header so
  it's unambiguous which branch the sprint landed on.
- Sweep your own leftovers: every worktree/branch you created this session must
  be gone (`git worktree list` + `git branch --list 'worktree-agent-*'` show
  none of yours). Leave foreign ones alone.
- Update `_state.md` / sprint index if the sprint uses one.
- **Slack the operator once** (memory `slack-notify` → Xure `mcp__slack__`, DM
  `U05MBLHE2J2`, NOT `claude_ai_Slack`): sprint name, the integration branch
  (`$BASE_BRANCH`), N done / N skipped / N blocked, head SHA, and that nothing
  was pushed.
- Remind: nothing was pushed; pushes are the operator's.

---

## 4. Guardrails / failure modes

- **Don't re-verify Done packets.** The operator trusts the marker.
- **Don't fake QA.** A SHAPE-row `Pass` must cite a green test (`Verified via
  tests/Feature/<path>`); a LIVE-row `Pass` must trace to a real run against
  the real dependency (live adapter / `tinker` / Playwright / `/horizon`) — a
  green Pest never clears a LIVE row. The Stop hook + the §2c manager audit are
  backstops, not the bar.
- **Don't widen scope.** Implement the packet, not the adjacent nice-to-have.
- **Don't serialize-block on a flaky external dep.** If a single QA case is
  truly operator-only (real OAuth, real partner config), mark it with the exact
  blocker and continue — that's the one accepted form of "not Pass".
- **Stale base is the #1 silent bug** — STEP 1 rebase is non-negotiable.
- **One fix = one commit** discipline does not apply here (this is packet work,
  not feedback triage); commit per packet (verify-done packets get a docs-only
  commit).
