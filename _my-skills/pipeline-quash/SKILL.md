---
name: pipeline-quash
description: Manually-invoked CI-failure lifecycle for ANY repo — provider (GitHub Actions or Bitbucket Pipelines) is auto-detected from the git remote. Invoke as `/pipeline-quash` with NO argument — it detects the provider, opens the LATEST CI run for the current branch in the user's authenticated Chrome, and checks whether it failed; only if it's red does it run the fix loop. Optionally pass `/pipeline-quash <run-url-or-#>` to target a specific run, or trigger when the user pastes a failed CI URL / run number / screenshot and says "pipeline failed", "CI is red", "fix the build", "the workflow failed", "quash this pipeline". Drives one red CI run to green: read the failed step/job logs straight from the provider's UI in Chrome (no API token needed) → cluster failures by root cause → reproduce each locally → fix (borrowing the bug-quash gates, chaining clean-code → vibesec) → verify locally → commit, NEVER push → after the user pushes, VERIFY THE NEW RUN in the provider UI in Chrome, monitoring the previously-red step to green → if still red, loop → Slack on each fixed-and-committed round and on the final green. If the repo develops inside a dev container and you're on the host, it first tells you to re-run inside the container. Targeted tests only, never the full suite. Session-only label CI-<n>; no external tracker.
---

# pipeline-quash — drive a red CI run to verified green (any repo, any provider)

You take **one failed CI run** — a GitHub Actions workflow or a Bitbucket
pipeline, whichever this repo uses — and walk it to green, one stage at a time,
stopping at the gates. A run is only "green for good" when you have **read the
real failure, reproduced it, fixed the root cause, watched the same step pass in
a *fresh CI run* — not just locally**, and looped until nothing is red. Anything
less gets reported honestly, not dressed up as done.

This is `bug-quash` for CI failures. It reuses that skill's discipline for the
fix (understand → reproduce → RCA → fix → verify → commit, never push, targeted
tests only, chain clean-code → vibesec) and wraps it with the two things a CI
failure adds: **reading the logs out of the provider's web UI in Chrome** (there
are usually no API creds locally, and private repos 404 anonymously), and
**verifying the fix in a real re-run** via that same UI, looping until the whole
run is green.

Nothing here is tied to a specific repo or CI host — the provider, the URLs, the
branch, the toolchain, and whether there's a dev container are all **detected**
(§0). Anything repo-specific you learn, treat as detected-not-assumed.

## Invocation, the session label & inputs

Invoked as **`/pipeline-quash`** — **no argument needed**. With nothing passed you
**default to the latest CI run** (see §0.5): detect the provider from the git
remote, open its runs list in Chrome, take the most recent run for the current
branch, and **check its status first** — only run the fix loop if it's actually red.

You *may* still **target a specific run** by passing an arg —
`/pipeline-quash <run-url-or-#>` — or by handing over a failed run (a GitHub
`…/actions/runs/<id>` or Bitbucket `…/pipelines/results/<N>` URL, a run number, or
a screenshot of a red run) with "pipeline failed" / "CI is red" / "quash this".
**An explicit target overrides the latest-run default.**

Give the run a **session-only** label `CI-<n>` (first this session →
`CI-1`, then `CI-2`, …); state it in your first line. Do **not** create any
external tracker — the label lives and dies with the session. Track the stages
with the task list (one task per stage, or one you check off) so the user sees
where the run is.

A pasted **screenshot** of the red run is a first-class input — transcribe the
failed step/job name and any visible error, then still open the live URL in Chrome
to get the full log.

## 0. Pre-flight — detect the repo context

Before loading Chrome tools, figure out *where you are and what you're driving*:

1. **Provider & URLs** — `git remote get-url origin` (or the remote the branch
   tracks) and read the host:
   - `github.com` → **GitHub Actions**. Runs list: `https://github.com/<owner>/<repo>/actions`
     (branch filter: `?query=branch%3A<branch>`); a run: `…/actions/runs/<id>`.
   - `bitbucket.org` → **Bitbucket Pipelines**. List: `https://bitbucket.org/<ws>/<repo>/pipelines`;
     a run: `…/pipelines/results/<N>`.
   - **GitLab / self-hosted / anything else** → the lifecycle is provider-agnostic;
     just ask the user for the runs-list URL and adapt the "read from the UI" steps.
   Parse `<owner>/<repo>` (or `<workspace>/<repo>`) from the remote — handle both
   SSH (`git@host:owner/repo.git`) and HTTPS (`https://host/owner/repo.git`) forms,
   strip the trailing `.git`.
2. **Branch & commit** — `git rev-parse --abbrev-ref HEAD` and the `HEAD` short SHA.
   The run you want by default is the newest one for **this branch** (ideally this
   commit).
3. **Dev-container gate** — if this repo **develops inside a container** and you're
   **on the host**, the fix loop (git, tests, commits) belongs *inside* that
   container, not on the host tree (which may be a stale or mounted copy):
   - **Already inside a container?** (`/.dockerenv` exists, or cwd is under a
     workspace mount like `/workspaces/…`, or `$HOME` is a container home) → **skip
     this gate**, continue to §0.5. (Check inside-first so you never bounce a user
     back into a container they're already in — `docker ps` still lists it via the
     mounted socket.)
   - **On the host** → does the repo use a dev container? Signals: a `.devcontainer/`
     dir, a compose service that looks like a dev box, or a `Makefile` target such as
     `dev-ssh`/`dev-up`. If so, is one **running**?
     `docker ps --format '{{.Names}}'` and look for a container named after this repo
     (compose defaults the project to the repo dir, so e.g. `<repo-dir>-dev-*`).
     - **Uses a container AND it's running** → do **not** proceed. Tell the user to
       enter it and re-run, then **stop**:
       > This repo builds inside a dev container. Enter it — `make dev-ssh` /
       > `ssh <host>` if the repo defines it, else `docker exec -it <name> bash` —
       > then run `/pipeline-quash` again inside it.
     - **Uses a container but it's stopped** → offer to start it (the repo's
       `dev-up`/compose command) then have them re-run inside; or, if they'd rather,
       proceed on the host and say the toolchain may differ.
     - **No dev container** → proceed right here on the host.

## 0.5 Resolve the target run

- **Explicit arg / URL / #** given → that's the target; go to §1.
- **No arg (default)** → open the provider's **runs list** in Chrome (filtered to the
  current branch when the provider supports it) and pick the **latest** run — the top
  row, ideally matching your `HEAD` SHA. **Read its status before doing any work:**
  - **Green ✓** → report "latest run #<N/id> (<branch> @<sha>) is green ✅ — nothing to
    quash" and **stop**.
  - **In progress** → say so; offer to watch it to completion (§8) or stop. Don't
    start a fix loop against an unfinished run.
  - **Red ✗** → that's your target; state its number/id + branch + SHA in your first
    line (so the user can redirect if it's the wrong run) and go to §1.

## Companion skills (chained)

- On the **fix**, load and apply `~/.claude/skills/clean-code/SKILL.md` then
  `~/.claude/skills/vibesec/SKILL.md` (clean-code auto-loads vibesec). Order of
  precedence on conflict: **vibesec > pipeline-quash > clean-code**.
- For a **high-risk** fix (auth, payments, money/ledgers, migrations, data
  deletion, jobs, webhooks, secrets, infra) say plainly it's in `/prod-safety-gate`
  territory — manual-invoke only, don't auto-load.
- To **notify** the user, invoke `~/.claude/skills/slack-notify/SKILL.md` — never
  just print "done".

---

## The pipeline (do not reorder, do not skip a gate)

```text
0 Pre-flight: detect provider/branch; inside dev container? (host + container running → send user in, stop)
  →  0.5 Resolve target (no-arg → latest run; green/in-progress → report & stop)
  →  1 Read the failure (provider UI in Chrome)  →  2 Cluster & diagnose  →  3 Reproduce (gate)
  →  4 Fix (branch; clean-code → vibesec)  →  5 Verify locally
  →  6 Commit (NEVER push)  →  7 Hand off + Slack
  →  8 Verify in CI (Chrome, monitor the re-run to green)
  →  9 Loop until green for good  →  10 Summarise
```

Three hard gates:
- **Reproduce gate (§3):** do not design a fix until you've reproduced the
  failure locally (or explicitly declared it CI-environment-only and reproduced
  it by forcing that condition locally — see §3).
- **Local-verify gate (§5):** do not commit until the targeted tests are green
  locally AND you haven't traded one red gate for another (run the format/lint
  gates on your changed files).
- **CI-verify gate (§8):** the bug is not fixed until a **fresh run** shows the
  previously-red step green. Local green is necessary, not sufficient.

---

## 1. Read the failure — from the provider UI in Chrome (no API token)

There is normally **no CI API credential** on the box, and private repos 404
anonymously. The user's Chrome **is** logged into the provider, so read the logs
there. This is the whole reason the skill exists.

1. Load the Chrome tools in ONE batched `ToolSearch` (they're often deferred):
   `select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__get_page_text,mcp__claude-in-chrome__tabs_create_mcp`
2. `tabs_context_mcp` (createIfEmpty:true) → open a **new** tab → `navigate` to the
   **target run resolved in §0.5** (for the no-arg default you're on the list, so
   open the latest red run).
3. **Screenshot** the run page to see the step/job status at a glance, then pull the
   log with **`get_page_text`** (far more reliable for logs than screenshots — use
   screenshots only for the status icons and to confirm the summary line). Provider
   specifics:
   - **GitHub Actions:** the run page lists **jobs** with ✓/✗. Open the **failed
     job**; its failed **step** usually auto-expands (click it if not).
     `get_page_text` the job log → every failing assertion / `✕` / `FAIL` block with
     `file:line` + message, plus the runner summary. The run header's **annotations**
     also summarize the failures. Logs are virtualized — scroll + re-`get_page_text`
     if it truncates.
   - **Bitbucket Pipelines:** the left **step rail** shows a ✓/! icon + duration per
     step. Open the **failed step**; `get_page_text` → every `FAILED …` block (test
     name, `file:line`, message) and the final `Tests: X failed, … , Y passed` line.
4. Record: which step/job failed, the exact failure count, and every failing
   `file:line` + message. Note which steps are **green** — those constrain the root
   cause (e.g. if lint/typecheck/build passed, it's a runtime/test failure, not a
   formatting one).

If Chrome can't reach the provider (not logged in, tab errors after 2–3 tries),
stop and ask the user — don't thrash.

## 2. Cluster & diagnose

Group the failing tests into **clusters by root cause** — a 12-failure step is
usually 2–3 causes, not 12. For each cluster:

- Distinguish a **genuine regression** (code/test that should pass and doesn't)
  from a **CI-environment-only** failure (a service, DB, or plane that CI
  deliberately doesn't provision, so the test connects to a dead endpoint). The
  fix differs: regression → fix code/test; env-only → make the test **skip
  cleanly** when the dependency is absent (guard *both* setup and teardown — a
  skipped test still runs teardown).
- Find the culprit commit: `git log --oneline -- <path>`, `git show <sha> --stat`
  (did the commit that changed behavior also update the dependent tests? a
  filtered local test run that "passed" often hid failures the full CI run
  surfaces).
- Confirm which branch the run was on and whether the culprit is only on that
  branch — this decides your merge target (§6).

## 3. Reproduce locally (gate)

Reproduce every cluster before fixing (the bug-quash reproduce gate). Discover the
test runner from the repo (`composer.json` / `package.json` / `Makefile` /
`pyproject.toml` / `go.mod` / `Cargo.toml` …):

- **Plain test failure** → run the targeted failing files with the project's runner
  (`vendor/bin/pest <file>`, `npx vitest run <file>`, `pytest <path>`, `go test ./pkg`,
  `cargo test <name>`, …). Confirm the same failures reproduce.
- **CI-environment-only failure** → the dependency that's dead in CI is usually **up
  locally**, so the test passes locally and hides the bug. Reproduce by **forcing
  that dependency dead** with an env override matching CI (e.g. point a host/port at
  a dead endpoint) → you must see the **same** CI error. Then, after the fix, run it
  **both** ways: dead → clean **skip** (not error); live → **pass** (no silent
  coverage loss).

If you can't reproduce, don't guess — state what you tried and ask for the missing
piece.

## 4. Fix (on a branch; smallest safe change)

- **Never work on the integration branch directly** (`main`/`master`/`dev`/`develop`).
  Branch off its current HEAD: `git checkout -b fix/ci-<n>-<slug>`. If the tree may
  be **shared with another agent**, scope every `git add` to your exact files; never
  `checkout .` / `clean` blanket. (Worktrees are often not worth it: a fresh worktree
  lacks installed deps, so the test runner can't run without a reinstall.)
- Apply the **smallest safe change per root cause** from §2 — fix the cause, not the
  symptom, no opportunistic refactors. For an intentional behavior change that broke
  stale tests, **update the tests to the new contract** (that IS the fix); mirror any
  pattern the culprit commit already used for its own updated tests. For an env-only
  failure, **guard the teardown/probe** the way sibling tests already do (find the
  established idiom).
- Apply the companion chain: clean-code (readable, comments say *why*) → vibesec
  (no security boundary weakened — enabling a feature flag *in a test tenant* to
  exercise a gated route does not weaken the production gate).

## 5. Verify locally (gate)

- Re-run the **exact** targeted files from §3 → the failures are gone (green; or
  clean **skips** for env-only tests, verified both dead- and live-dependency).
- Don't trade one red gate for another: run the **format/lint gates on your changed
  files only** — and know which paths each gate actually analyses (a static-analysis
  or lint config may **exclude `tests/`**, so a test-only diff is neutral to it).
  Never run the whole suite for a CI fix.
- Review `git diff`: no debug prints, no secrets, no unrelated churn; every line
  traces to a cluster.

## 6. Commit — NEVER push

The user reserves all `git push`. Merge your fix branch into the **branch the CI run
was on** (whichever integration branch that is — merging a `dev`-only fix into
`main` is wrong):

```bash
git checkout <integration-branch>            # the branch the run was on
git merge --no-ff fix/ci-<n>-<slug> -m "fix(ci): CI-<n> <what> — <why>"
git rev-parse --short HEAD                    # report this SHA
git branch -d fix/ci-<n>-<slug>              # merged; -d is safe
```

If there's no git identity configured, commit with inline
`-c user.name=… -c user.email=…`. End the message with the repo's required trailer
if it has one. Verify the tree was clean before you branched and that you only staged
your files (shared tree).

## 7. Hand off + Slack

Surface the merge SHA and tell the user the fix is committed and **needs their push**
to trigger a re-run. Invoke `slack-notify` (⚠️ shape — it's an action for them):
"CI-<n> fixed + committed at `<sha>` — push `<branch>` to re-run." Then proceed to §8
to watch the run they trigger.

## 8. Verify in CI via Chrome — monitor the re-run to green (the point of this skill)

After the user pushes, a **fresh run** starts. Watch it in Chrome; local green is not
proof.

1. In Chrome, navigate to the runs **list** (`…/actions` or `…/pipelines`). The new
   run is the newest entry; confirm it's **your commit** (the merge SHA / message) on
   the right branch, and **in progress**.
2. Open it and screenshot the step/job view. Note which step you're waiting on (the
   one that was red) and its **typical duration** (a big test job can be 20–25 min;
   other jobs run in parallel and finish first).
3. **Wait without idle-polling.** Foreground `sleep` is blocked; run `sleep <seconds>`
   **in the background** (`run_in_background: true`) — it re-invokes you when it exits.
   Pick the interval from the step's remaining time (e.g. first check ~9 min in, then
   ~5, then ~3 near the end). Don't burn a foreground turn waiting.
4. On each wake: re-`navigate` to the run and screenshot / `get_page_text`. Read the
   target step/job:
   - **Still running** → schedule the next background `sleep` and wait.
   - **Green ✓** → open it, grab the test-summary line as evidence, and confirm the
     **whole run** header is green (all steps/jobs ✓, including any that were
     previously skipped/"Not run" because the failed step blocked them).
   - **Red again** → drill into the new failure with `get_page_text` (it may be the
     same cluster returning, or a brand-new one) and go to §9.

## 9. Loop until green for good

If the re-run is still red, treat the new failure as the next round of the same CI-<n>
run: back to §1/§2 for that failure → reproduce (§3) → fix (§4) → verify (§5) → commit
(§6) → hand off + Slack (§7) → watch the next re-run (§8). Repeat until a fresh run is
**fully green**. Never call it done on a run you didn't watch turn green.

## 10. Summarise

```md
## CI-<n> — CI green ✅
- **Was:** run #<X> red at step/job "<name>" — <N> failures (<clusters>)
- **Root cause(s):** <one line per cluster, file:line + culprit commit>
- **Fix:** <what changed, files> (test-only? prod code?)
- **Local evidence:** <targeted cmd> green; env-only tests skip-when-dead / pass-when-live
- **CI evidence:** run #<Y> (<branch> @<sha>) GREEN — step "<name>" ✓, all steps ✓
- **Merged:** <branch> @<sha> (not pushed by me — user pushed)
- **Rounds:** <how many fix→push→rerun cycles>
- **Follow-ups / risks:** <backfill, related latent failures — or "none">
```

Never write "green" if you didn't watch a fresh run turn green — report the real
state and what's blocking.

---

## Operating rules (override convenience)

- **One run at a time**, driven to green. Multiple red runs → sequential.
- **Detect, don't assume** — provider (GitHub/Bitbucket/other), URLs, branch,
  toolchain, and dev-container setup all come from the repo (§0), not from memory.
- **Read logs from the provider's web UI in Chrome** — no local API token; don't try
  to curl the API, and never paste secrets to get one.
- **Never push.** Commit + surface the SHA; the user pushes and you watch the run.
- **Never run the full suite** for a CI fix — targeted files only.
- **Reproduce before fixing, verify in a fresh CI run before declaring green** — the
  local-green/CI-red trap is exactly what this skill exists to close.
- **Smallest safe change**, root cause not symptom; for CI-env-only failures, make the
  test skip cleanly (guard setup **and** teardown), don't disable it.
- **Honest status** — a run you didn't watch turn green is not green.

## Reference — worked example from one repo (illustration, not a requirement)

Concrete details are repo-specific and must be **detected** (§0); this is just an
example of the *kinds* of things the skill runs into, from the repo it was first built
on (a Laravel + Vue monorepo on Bitbucket Pipelines, developed inside a dev container):

- **Provider:** Bitbucket, remote `git@bitbucket.org:<ws>/<repo>.git` → pipelines at
  `bitbucket.org/<ws>/<repo>/pipelines`. Private → Chrome UI only, no API creds.
- **Integration branch was `dev`**, not `master` — merge fixes to the branch the run
  was on.
- **Dev container:** on the host, `docker ps` showed `<repo>-dev-*` running; the fix
  loop had to run inside it (`make dev-ssh`). The host tree there was a frozen backup —
  a perfect example of *why* §0's container gate exists.
- **A CI-environment-only cluster:** CI omitted a whole service plane (no
  `pgsql_dsp` / `redis_dsp_cfg` → fell back to a dead `127.0.0.1:6390`, no object
  store). Those tests passed locally (plane up) and failed in CI (plane down) — the
  classic §3 env-only trap. Fix = self-skip by probing **every** tier they touch, in
  setup *and* teardown; reproduce by forcing a tier dead locally
  (`REDIS_DSP_CFG_PORT=6390 …`).
- **Toolchain** (`code/backend`): `vendor/bin/pest [<file>]`, `vendor/bin/pint --test <files>`,
  PHPStan **excluded `tests/`**, `vendor/bin/deptrac` (app/ only), `npx vitest run <file>`.
- **Shared git tree** (a second agent may be committing): scope `git add` to exact
  files; never blanket `checkout`/`clean`.
- **Slack** went through the `slack-notify` skill (a bot identity), not any web
  connector.
