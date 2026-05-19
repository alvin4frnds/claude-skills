# Job folder format

Reference for what the GitMdAnnotations Android app writes under `jobs/pending/<jobId>/` on the `claude-jobs` branch. This is the input format for the `claude-jobs` skill.

## Source of truth vs. snapshot

Everything under `jobs/pending/<jobId>/` is a **snapshot** of what the user reviewed. The actual editable document lives elsewhere in the repo — at the path captured in the `imported-from` provenance comment of `02-spec.md` (or in the import commit message for PDF specs). All edits the skill produces go to that original path; the snapshot folder is archived intact to `jobs/done/<jobId>/`.

## Folder naming

`<jobId>` is a slug derived from the source filename (e.g. `api-rate-limit.md` → `spec-api-rate-limit`). Treat it as opaque.

## Files for a markdown-source spec

| File | Purpose |
|---|---|
| `02-spec.md` | The imported markdown. First two lines are HTML comments: `<!-- gitmdscribe:imported-from=<original-path> -->` and `<!-- gitmdscribe:imported-at=<ISO8601> -->`. Rest is the original body. May include an appended changelog section after review. |
| `03-review.md` | Present only after the user has submitted a review on the tablet. Structure: `# Review — <jobId>`, `**Source:** 02-spec.md @ <sha>`, answers to open questions, free-form notes, spatial references to stroke groups. |
| `03-annotations.svg` | Vector strokes (user's handwriting). Probably not needed by Claude. |
| `03-annotations.png` | Flattened raster of strokes only. |
| `03-annotations.pdf` | **Composite** — spec rendered as background with strokes on top. Best single file to visually inspect what the user annotated. |
| `03-annotations.json` | Sidecar with stroke metadata — anchors (which line each stroke attaches to), stroke groups (A, B, …, AA, AB for >26), timestamps. **Known caveat:** if every group's `lineNumber` is `1`, the app hit its placeholder-anchor fallback — treat the JSON line anchors as garbage and rely on the composite PDF/PNG instead. |

## Files for a PDF-source spec

| File | Purpose |
|---|---|
| `spec.pdf` | Original PDF, untouched. Provenance is in the import commit message. |
| `03-review.md` | Same as above. |
| `03-annotations-p<N>.svg` | Per-page vector strokes (one file per page). |
| `03-annotations-p<N>.png` | Per-page flattened raster. |
| `03-annotations.json` | Same sidecar shape as above. |
| `CHANGELOG.md` | Changelog sidecar (PDFs can't carry inline changelog like `.md` specs). |

## Phase signals

The `claude-jobs` skill does not need to read phase state — it infers work to do by the presence of `03-review.md`. For reference, the app's phase state machine is:

- `spec` — only `02-spec.md`/`spec.pdf` present. **Not processed by this skill** (user hasn't reviewed yet).
- `review` — `03-review.md` + annotations present. **This is the trigger.**
- `revised` — Claude has implemented and moved the folder to `jobs/done/`. App UI updates on next Sync Down.
- `approved` — user approved the revision; `05-approved` marker file present. No Claude action needed.

## Done-state

When a job is complete, the folder is moved as a whole unit to `jobs/done/<jobId>/` on `claude-jobs`. Nothing inside the folder is edited; the move is a pure `git mv`.
