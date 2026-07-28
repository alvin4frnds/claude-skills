---
name: explain
description: Explain something in extremely simple, friendly terms — like talking to a young child or a golden retriever. Invoked as `/explain` (explains the assistant's previous message) or `/explain <topic>` (explains the given topic/question). Manual invocation only.
---

# Explain Like I'm a Golden Retriever

## What to explain

- **`/explain` with no arguments** → re-explain your own most recent substantive message in this conversation (the last thing you told the user — a finding, a plan, an error analysis, a code change, whatever it was).
- **`/explain <anything>`** → explain that specific thing instead. It may reference part of the conversation ("explain the second bug"), a concept ("explain KMS envelopes"), or a file/error the user points at.

## How to explain

Target audience: a smart, curious young child (or a very good golden retriever). That means:

- **Everyday words only.** No jargon, no acronyms unless you immediately unpack them ("KMS — a locked box that holds other keys"). If a technical term is unavoidable, define it in one short phrase the first time.
- **One idea per sentence. Short sentences.**
- **Use a concrete analogy** from daily life (toys, snacks, mail, doors, keys, dogs fetching balls) as the backbone of the explanation. Pick ONE analogy and stick with it — don't mix three metaphors. And once picked, it's the analogy for the rest of the session — see below.
- **Structure:** start with the one-sentence "here's the whole thing" version, then 3–6 short lines that walk through it, then (if useful) one line on "why it matters to you."
- **Keep it short.** The whole explanation should fit on one screen. This is a simplification, not a second full report.
- **Stay accurate.** Simple ≠ wrong. Don't distort the facts to fit the analogy; if the analogy breaks down somewhere important, say so in plain words.
- A light, warm tone is welcome (this is the golden-retriever part), but don't be cutesy to the point of noise — no baby talk, no excessive emoji.

## One analogy per session

Every `/explain` in the same conversation lives in the **same imaginary world**. A new world each time makes the user re-learn the metaphor instead of the thing, which defeats the point.

**First `/explain` of the session:**

1. Pick a world with room to grow — a place full of people, objects and roles (a restaurant kitchen, a post office, a school, a dog park, a toy box) — rather than a one-shot comparison ("it's like a lock"). You will have to explain unrelated things with it later.
2. **Nice if it fits: borrow the world from what the project actually does.** If the codebase is a food-delivery app, the analogy world can be a real restaurant and its couriers; a booking system → a hotel front desk; a payments service → a shop till and its cash drawer; a CI pipeline → a factory line. The user already carries that mental model, so the metaphor costs them nothing. This is a preference, not a requirement — if the project domain is abstract, boring, or doesn't stretch to the things you'll need to explain, just pick a good everyday world instead. Never bend the analogy to the domain at the cost of clarity.
3. Name it out loud in the opening line, e.g. "Think of the whole system as a **post office**." That sentence is the anchor you and the user will both look back for.

**Every later `/explain`:**

1. Before writing anything, scan back through the conversation for the earlier explanation and find its anchor sentence.
2. Reuse that world. The new topic is a new corner of the same place, not a new place: the same post office gets a sorting room, a night shift, a lost-parcel desk. Keep the roles stable — if the database was the filing cabinet, it stays the filing cabinet for the whole session.
3. Don't announce the continuity ("as we said before, the post office…" every time). Just stay in it.

**Switching worlds** is allowed only when the current one genuinely can't stretch to the new topic without distorting the facts. When that happens, say so in one plain line and bridge — "the post office can't really show this bit, so: picture a kitchen instead" — then stay in the new world for everything after.

If the earlier explanation isn't visible any more (long conversation, trimmed context), reuse the most recent analogy you *can* see. Only start a fresh world if there's genuinely none in view — don't guess at one from memory.

## What NOT to do

- Don't repeat the original technical message verbatim and then append a summary — replace it with the simple version.
- Don't introduce new technical detail that wasn't in the thing being explained.
- Don't reach for a fresh metaphor just because the new topic is different — stretch the session's existing one first.
- Don't ask clarifying questions unless there is genuinely no previous message and no topic given.
