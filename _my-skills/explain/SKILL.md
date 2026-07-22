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
- **Use a concrete analogy** from daily life (toys, snacks, mail, doors, keys, dogs fetching balls) as the backbone of the explanation. Pick ONE analogy and stick with it — don't mix three metaphors.
- **Structure:** start with the one-sentence "here's the whole thing" version, then 3–6 short lines that walk through it, then (if useful) one line on "why it matters to you."
- **Keep it short.** The whole explanation should fit on one screen. This is a simplification, not a second full report.
- **Stay accurate.** Simple ≠ wrong. Don't distort the facts to fit the analogy; if the analogy breaks down somewhere important, say so in plain words.
- A light, warm tone is welcome (this is the golden-retriever part), but don't be cutesy to the point of noise — no baby talk, no excessive emoji.

## What NOT to do

- Don't repeat the original technical message verbatim and then append a summary — replace it with the simple version.
- Don't introduce new technical detail that wasn't in the thing being explained.
- Don't ask clarifying questions unless there is genuinely no previous message and no topic given.
