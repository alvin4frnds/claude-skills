---
name: deep-research-claude
description: Run multi-step, citation-grounded research using Claude's built-in WebSearch and WebFetch — no external API key, no per-task cost. Use when the user asks for "deep research", "literature review", "market analysis", "competitive landscape", "technical investigation", "due diligence", or otherwise wants a thorough, sourced report on a topic that exceeds what a single web search can answer. Claude-native replacement for Gemini Deep Research; runs entirely inside Claude Code.
---

# Deep Research (Claude-native)

Multi-step research workflow producing a structured, cited report. Built on Claude Code's `WebSearch`, `WebFetch`, and (optionally) parallel `Agent` subagents — no external services, no API keys.

## When to use

Trigger when the user asks for:

- Deep research, literature review, market analysis, competitive landscape, due diligence.
- Technical investigation across multiple primary sources (specs, RFCs, vendor docs).
- A sourced report — i.e., something where citations matter and a single web search isn't enough.
- "Build a doc on X", "give me a comprehensive overview of Y" — when *Y* is broad enough that 3+ searches and 3+ source reads are needed.

Do **not** trigger for:

- Single-question lookups ("what's the latest version of X?") — just use `WebSearch` directly.
- Coding tasks that happen to involve web docs — use `Agent` with `subagent_type: claude-code-guide` or just `WebFetch` ad-hoc.
- Internal-codebase questions — use `Agent` with `subagent_type: Explore`.

## What this replaces

This is a Claude-only successor to the `deep-research/` skill, which calls Google's Gemini Deep Research Agent ($2-5/task, 2-10 min). This version uses Claude's own tools, runs in seconds-to-minutes, and has no per-task cost beyond your existing Claude Code session.

The trade-off: this runs **only inside Claude Code**. For headless / CI use, fall back to the original `deep-research/` skill or use the Anthropic SDK directly.

## Procedure

Follow these steps in order.

### 1. Capture and clarify scope

The user's request is the research question. If it has 3+ ambiguities (audience? depth? scope? output format?) ask **one** consolidated `AskUserQuestion` covering at most 3 of them. If the question is concrete, skip this step.

Default assumptions when not specified:

- **Audience**: technical/engineering reader.
- **Depth**: 8-15 page report (~5,000-8,000 words).
- **Output**: a single Markdown file. Path defaults to `~/Downloads/<slug>.md` unless the user names another location.
- **Citations**: inline links + a References section at the end.

### 2. Plan the research

Write 3-7 **sub-questions** that, taken together, answer the user's request. Examples:

- For "research the Rust async ecosystem in 2026" — sub-questions might be: state of tokio vs async-std vs smol; std::async stabilization status; structured concurrency proposals; popular runtimes for embedded; production adoption surveys.
- For "compare Snowflake vs Databricks for our workload" — sub-questions: pricing models 2026; performance benchmarks on similar workloads; governance/Iceberg support; ecosystem and ML integration; recent customer migrations.

Keep this list internal — don't dump it on the user before researching. They will see it reflected in the report's section headings.

### 3. Search broadly (parallel)

Issue **all sub-question searches in a single message** with parallel `WebSearch` tool calls. This is the breadth pass.

For each sub-question, prefer:

- Official sources (vendor docs, RFCs, standards bodies, GitHub repos).
- Recent material — include the current year in queries when recency matters.
- Multiple angles per sub-question (e.g., "X benchmarks 2026", "X production experience", "X criticism").

If the topic is large (10+ sub-questions, or the user explicitly asks for "exhaustive"), instead **delegate breadth to a parallel `Agent` (general-purpose) batch**: spawn 2-3 agents with different scopes, run in parallel, and merge their findings.

### 4. Read primary sources (depth pass)

From the search results, pick the **3-8 most authoritative URLs** per sub-question and `WebFetch` them with a focused prompt — not "summarize this page", but "extract X, Y, Z from this page".

Notes:

- For GitHub repos, prefer reading the spec/Markdown source (e.g., `github.com/foo/bar/blob/main/SPEC.md`) over the rendered HTML.
- Avoid SEO-farm content — prefer vendor blogs, standards bodies, well-known engineering blogs (e.g., Cloudflare, Stripe, Discord, GitHub Engineering).
- If a primary source is paywalled or auth-gated (Confluence, internal Jira, etc.), `WebFetch` will fail — note the gap and continue.
- Cache discipline: `WebFetch` has a 15-min cache. Don't fetch the same URL twice.

### 5. Synthesize

Compile a structured report with this default skeleton (adapt section count to scope):

```
# <Title>

*Audience: <one line>*
*Last updated: <month year>*

## 1. Executive summary
## 2. <First sub-topic>
## 3. <Second sub-topic>
...
## N. Key takeaways / recommendations  (only if user asked for a recommendation)
## Appendix: References
```

Rules:

- **Cite specific claims**, not generic ones. Inline as `[short label](https://...)` or numbered footnote-style — pick one and stay consistent.
- Don't fabricate citations. If you didn't fetch a source, don't cite it.
- Prefer **tables** for comparisons (vendor X vs Y, version A vs B).
- Prefer **bullet lists** only for genuinely list-shaped content; use prose elsewhere.
- ASCII diagrams are fine for architecture / flow; offer Mermaid only if the user has confirmed they'll render it.
- Mark uncertainty explicitly — "as of <date>", "per <source>; conflicting numbers in <other source>".

### 6. Write the file (or return inline)

Default: write to `~/Downloads/<topic-slug>.md`.

If the user has stated a different path or asked for inline output, follow that instead. Confirm the path with the user **only if they didn't specify and the default may surprise them** (e.g., they're in a project repo and `./docs/` would be more natural).

### 7. Self-check before reporting completion

Before telling the user the doc is done, run these checks:

1. **Word count** is in the requested ballpark (default target 5,000-8,000 words).
2. **References section** lists every URL actually cited — and only those.
3. **No invented sources**. If you couldn't fetch something, the citation isn't there.
4. **Spec / numerical claims sampled**: pick 2-3 specific factual claims and confirm they match what the source actually says. Fix any drift.
5. **JSON / code blocks parse** if the doc includes them (run `python3 -c "import json; json.loads(open(...).read())"` on extracted blocks where applicable).

Report results in 1-2 sentences: file path, word count, sections, and any gaps you noted.

## Output format options

If the user invokes this skill with a `--format` hint or specific structure request, honor it. Common variants:

- **Briefing memo** (1-2 pages): exec-summary first, no references section, three takeaways.
- **Technical reference** (default): full sections, citations, glossary if jargon-heavy.
- **Comparison matrix**: a table is the centerpiece; sections are short.
- **Decision doc**: sections for context → options considered → recommendation → risks.

## Edge cases

- **Recency-sensitive topic** (latest model versions, current pricing, "as of today" claims): include the current year in every search query, fetch the vendor's most recent blog/announcement, and date every claim in the doc.
- **Topic spans multiple verticals** (e.g., "RTB" touches programmatic ad-tech, web standards, privacy regulation): plan separate sub-questions per vertical — don't try one mega-search.
- **Topic is well-covered in Claude's training data**: still cite primary sources for any claim that could date or change. Don't lean on memory for facts the reader will check.
- **Topic is too narrow for "deep" research** (e.g., one specific API endpoint): do one or two `WebFetch`es and answer inline; don't over-engineer a 10-page report.
- **User asks to continue / elaborate** on a previous report: read the prior `.md` file first, then run a focused depth pass on the requested expansion area.
- **`WebSearch` is US-only**: for non-US-specific queries this is fine, but flag if results seem geo-skewed.

## Quick reference

| Step | Tool | Parallel? |
|------|------|-----------|
| Plan | (Claude reasoning) | n/a |
| Breadth search | `WebSearch` | yes — one message, many calls |
| Optional breadth-via-agent | `Agent` (general-purpose) | yes — up to 3 in parallel |
| Depth read | `WebFetch` | yes for unrelated URLs |
| Synthesize | (Claude reasoning) | n/a |
| Write | `Write` | no |
| Self-check | `Bash`, `Read` | mostly sequential |

## Anti-patterns

- One giant `WebSearch` per topic, then fetching every result. Wastes time, dilutes signal — pick a few authoritative sources.
- Writing the report from search-result snippets without `WebFetch`ing primaries. Snippets are summaries of summaries; they're often wrong on details.
- Burying conclusions at the end. Lead with the executive summary; the deep sections back it up.
- Citing Wikipedia for technical specs when the underlying RFC / vendor doc is one click away.
- Adding a "Methodology" section to explain how Claude did the research. The reader wants the answer, not the process.
