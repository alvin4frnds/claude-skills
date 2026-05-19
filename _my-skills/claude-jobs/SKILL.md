---
name: claude-jobs
description: This skill should be used when the user asks to "process pending jobs", "drain the claude-jobs queue", "work on jobs from the tablet", "run claude-jobs", or invokes `/claude-jobs`. It pulls reviewed specs from the `claude-jobs` branch of a GitMdAnnotations-style repo, implements each one as a commit on the current branch, and archives the job folder to `jobs/done/` on `claude-jobs`. Do not invoke proactively — only when the user explicitly asks.
version: 0.1.0
---

# claude-jobs — queue drainer

The paired Android app (GitMdAnnotations) stores reviewed work items on a sidecar branch `claude-jobs` under `jobs/pending/<jobId>/`. Each reviewed folder contains `02-spec.md` (or `spec.pdf`), `03-review.md`, and `03-annotations.{svg,png,pdf,json}` — a **snapshot** of what the user reviewed on the tablet.

This skill drains that queue: fetch → for each job, read the snapshot + the user's review + the annotation images → edit the **original source file** (the .md the user imported from, captured in the `imported-from` provenance comment) → commit → archive the snapshot folder to `jobs/done/` on `claude-jobs` → push → loop until empty.

The `jobs/` tree is tablet-side bookkeeping. The source of truth for content edits is the original file back in the main working tree.

See `references/job-format.md` for the exact folder layout the app produces.

## When to run

Run only when the user explicitly asks (e.g. `/claude-jobs`, "drain the queue", "process pending jobs"). Never invoke automatically. The skill makes commits on the user's current branch, so the user needs to be ready for that.

## Preflight

Do all of these before touching anything. Stop with a clear message if any check fails.

1. **Repo check** — `git rev-parse --show-toplevel` must succeed.
2. **Remote check** — `git ls-remote --heads origin claude-jobs` must return a line. If empty, stop: *"No `claude-jobs` branch on origin yet. Nothing to process — the tablet app creates this branch when you import your first spec and Sync Up."*
3. **Branch check** — `git rev-parse --abbrev-ref HEAD`. If it is `claude-jobs`, stop: *"You're currently on `claude-jobs`. Switch to a code branch (usually `main`) before running this skill — job commits land on the current branch."*
4. **Clean tree check** — `git status --porcelain`. If it has any output, stop: *"Working tree has uncommitted changes. Commit or stash them first; job commits must not sweep in unrelated work."*

## Prepare the worktree

The skill uses a git worktree at `<repo>/.claude-jobs/` as both the readable copy of the jobs folder and the staging area for archive commits.

1. Ensure `.claude-jobs/` is in `.gitignore`. If not, add a line and commit it on the current branch with message `chore: ignore .claude-jobs worktree` — this is a one-time setup commit.
2. `git fetch origin claude-jobs`
3. If `<repo>/.claude-jobs/` does not exist → `git worktree add -B claude-jobs .claude-jobs origin/claude-jobs`.
4. If it exists → `git -C .claude-jobs fetch origin claude-jobs` then `git -C .claude-jobs reset --hard origin/claude-jobs`. (Hard reset is safe: this worktree only ever holds upstream state plus our own fresh archive commits, never user edits.)

Do not delete the worktree at the end of the run. Leaving it gives the user a place to inspect state. Tell them the cleanup one-liner in the final report: `git worktree remove .claude-jobs`.

## Enumerate jobs

List directories under `.claude-jobs/jobs/pending/`. Keep only those where `03-review.md` exists. Sort by folder name (lexicographic) so ordering is deterministic.

If the filtered list is empty, report *"No pending reviewed jobs. Queue is drained."* and stop. Do not error.

## Per-job loop

Process one job at a time. After each successful job, re-run **Enumerate jobs** — new ones may have landed via a concurrent Sync Up.

For each `<jobId>`:

### 1. Read the job brief

Read every file that exists. Use the `Read` tool for all of them (it handles markdown, JSON, PDF, and PNG).

- `.claude-jobs/jobs/pending/<jobId>/02-spec.md` — if present. Line 1 is `<!-- gitmdscribe:imported-from=<source-rel-path> --> ` (the **original source file** path, repo-relative — remember this, it's your edit target). Line 2 is `<!-- gitmdscribe:imported-at=... -->`. Strip both before treating the rest as content.
- `.claude-jobs/jobs/pending/<jobId>/spec.pdf` — if present instead of `02-spec.md`. Provenance is in the import commit message (`git -C .claude-jobs log --format=%B -n 1 -- jobs/pending/<jobId>/spec.pdf` → look for `Import <source-rel-path> as <jobId>`).
- `.claude-jobs/jobs/pending/<jobId>/03-review.md` — the user's typed review. Always present (that's our filter).
- `.claude-jobs/jobs/pending/<jobId>/03-annotations.json` — stroke anchors. Light read; used if the review references strokes spatially. **Known caveat:** if every stroke group's `lineNumber` is `1`, the app hit a placeholder-anchor fallback and the JSON line anchors are **garbage** — ignore them and rely on the annotations PDF/PNG instead.
- For `.md` specs: `.claude-jobs/jobs/pending/<jobId>/03-annotations.pdf` — a composite of the spec with the user's strokes overlaid. **Always read this**; it's the highest-signal view of what the user wanted.
- For `.pdf` specs: all `.claude-jobs/jobs/pending/<jobId>/03-annotations-p<N>.png` files, in page order.

### 2. Identify the edit target

The **source of truth is the original file in the repo working tree** — everything under `jobs/` is tablet-side bookkeeping and must not be edited by the skill.

From the provenance captured in step 1:

- Resolve `<source-rel-path>` to an absolute path: `<repo-root>/<source-rel-path>`.
- Verify the file exists in the main working tree. If missing (file was renamed or deleted since import), **skip this job** with reason *"source file `<path>` no longer exists"*, and move on.
- Record this path. All code/content edits for this job target this file (and any files it references if the review explicitly names them).

### 3. Plan and implement

Use this precedence for interpreting the review:

1. **Typed content in `03-review.md`** (answers to open questions, free-form notes) — primary instruction when non-empty.
2. **Handwritten annotations in `03-annotations.pdf` / `-p<N>.png`** — primary instruction when the typed review is empty or near-empty, supplement otherwise. Read the composite PDF as an image; the user's strokes show you *spatially* what they marked up.
3. **`02-spec.md` / `spec.pdf`** — context only. It's the snapshot the user was reviewing.
4. **`03-annotations.json`** — optional spatial hints *only* if stroke anchors look sane (not all line 1). Skip otherwise.

Empty-typed-review is **not** grounds to skip on its own. If the annotations PDF shows clear handwritten instructions (e.g. arrows, crossed-out sections, margin notes with legible text), proceed on that alone. The user drew those strokes *because* they had something to say.

Make the edits in the main working tree, targeting the file(s) identified in step 2. Use Edit/Write/Bash as normal. Keep the scope to what the review/annotations ask for; don't refactor adjacent content unless explicitly requested.

**Skip** (don't guess) only when *all* of these are true:
- Typed review has no actionable content.
- Annotation images are illegible, ambiguous, or contain no clear directive (e.g. a lone circle with no label, or a `?` with no target).
- No identifiable source file path.

When you skip, record a short reason for the final report and move to the next job. Leave the pending folder untouched so the user can re-review it on the tablet.

### 4. Commit on the current branch

Stage only the files you changed (never `git add -A` — avoid sweeping in the user's untracked work). Commit with:

```
<jobId>: <one-line summary derived from the review>

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

Do **not** push the current branch. The user pushes manually (their rule: "commit often, never push").

### 5. Archive on claude-jobs

In the worktree:

```
git -C .claude-jobs mv jobs/pending/<jobId> jobs/done/<jobId>
git -C .claude-jobs commit -m "done: <jobId>"
git -C .claude-jobs push origin claude-jobs
```

If the push is rejected (non-fast-forward — someone else pushed to `claude-jobs` during the run):

```
git -C .claude-jobs fetch origin claude-jobs
git -C .claude-jobs rebase origin/claude-jobs
git -C .claude-jobs push origin claude-jobs
```

Retry **once**. If the second push still fails, stop the whole skill run and surface the error. Never `--force` or `--force-with-lease` — the sidecar branch is shared with the tablet and an overwrite would lose new specs.

### 6. Consistency window

Between step 4 (main commit) and the successful archive push in step 5, there is a brief window where the source change exists locally but the sidecar still shows the job as pending. If step 5 fails irrecoverably, **do not** roll back the step-4 commit. Surface the inconsistency in the final report so the user can either retry the archive by hand or `git reset HEAD~1` the code commit themselves. Auto-rollback is riskier than leaving the state observable.

## Loop and finish

After a successful job, go back to **Enumerate jobs**. Stop when the filtered list is empty.

Report at end:

- Jobs completed: list of `<jobId>` with main-branch commit SHA and archive commit SHA.
- Jobs skipped: list of `<jobId>` with reason (ambiguous review, missing files, etc.).
- Cleanup hint: `git worktree remove .claude-jobs` if they want the worktree gone.

## Hard guardrails

- **No force-push** to `claude-jobs`, ever.
- **No commit amends** on either branch.
- **No pushing** the current/main branch.
- **No deleting** the worktree automatically.
- **No processing** jobs without `03-review.md`.
- **No edits** to anything under `jobs/` in the main working tree — that's tablet-side state. Edit the original source file identified by the `imported-from` provenance.
- **No guessing** when both the typed review and the annotation images are unreadable — skip and report.
- **No `git add -A`** in the main tree — stage only files changed for the current job.
