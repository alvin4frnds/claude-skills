---
name: share-diagram
description: Render a diagram as PNG and share it inline in the user's Slack DM. Triggers on "send me a diagram of X", "draw and share X", "diagram + slack", "send the architecture diagram to slack", or any combination of "diagram/chart/flow/architecture/sketch" plus "slack/dm/share/send me". Pipeline is local SVG (or Mermaid) → ImageMagick PNG → Dropbox upload + public share link → Slack post with the `?raw=1` URL so Slack unfurls the image inline. Pairs with `visuals-claude` (generates SVG) and reuses `slack-notify`'s message tooling. Requires Dropbox token + ImageMagick installed.

---

# share-diagram — render + host + post a diagram to Slack inline

This skill is for when the user wants a diagram **visible inside Slack** (not just a clickable link to claude.ai/code). It packages the full pipeline:

```
visuals-claude → SVG  →  ImageMagick → PNG  →  Dropbox upload + share  →  Slack DM (inline preview)
```

## When to use this skill vs. the alternatives

- **share-diagram** — user wants the rendered image to appear directly in Slack, scrollable in DM history.
- **slack-notify** — user wants a *notification* in Slack, with a clickable URL back to the live Claude session (where Mermaid/SVG renders natively).
- **visuals-claude alone** — user is in Claude Code and just wants the diagram rendered in the conversation.

If the user says "send me the diagram on slack so I can see it on my phone", that's share-diagram. If they say "ping me on slack when the diagram's ready", that's slack-notify with a Mermaid block in the linked session.

## Required prerequisites

1. **Slack MCP server installed and connected** — exposes `mcp__slack__conversations_add_message`. Same as `slack-notify`.

2. **Dropbox API token** — Required for the upload step. Mint via the refresh-token helper:
   - Run `~/.dropbox-token-fresh.sh` → prints a fresh `sl.u.…` access token to stdout. Cached in `~/.dropbox-token-cache.json` for ~4h, auto-refreshed via OAuth `refresh_token` grant when expired.
   - Helper reads credentials (refresh_token + client_id + client_secret) from `~/.dropbox-refresh.json` (chmod 600).
   - Fallbacks (legacy): env var `DROPBOX_TOKEN`, then file `~/.dropbox-token` (static token).

   If neither helper nor fallback works, do not silently fall back to ASCII or a third-party host. Stop and tell the user. To bootstrap from scratch, walk them through OAuth: `https://www.dropbox.com/oauth2/authorize?client_id=<APP_KEY>&token_access_type=offline&response_type=code` → exchange the returned code at `https://api.dropbox.com/oauth2/token` (`grant_type=authorization_code`) → store the `refresh_token` + key + secret in `~/.dropbox-refresh.json`.

   Usage in the pipeline: `TOKEN="$(~/.dropbox-token-fresh.sh)"` — never embed a raw token.

3. **ImageMagick installed** — needed to convert SVG → PNG. On Windows, the binary is at `C:\Program Files\ImageMagick-*-Q16-HDRI\magick.exe`. On macOS/Linux it's typically just `magick` on PATH.
   - Detect at the start of the procedure (try `magick --version` or look up the install path on Windows).
   - If missing, tell the user to install: Windows: `winget install ImageMagick.ImageMagick`; macOS: `brew install imagemagick`; Linux: `apt install imagemagick`.

## Delegation model

Step 1 (SVG generation) runs on the parent (main thread / Opus) — that's the model-judgment step (what to draw, layout, labels). Everything after — PNG render, Dropbox upload, share link, `?raw=1` rewrite, Slack post — runs inside a Sonnet sub-agent spawned via the Agent tool. This skill is a cleaner delegation case than `slack-notify` because there's no mobile-push entanglement: the parent has nothing transcript-sensitive to emit after the agent returns, so the entire post-SVG pipeline collapses into a single sub-agent call.

| Step | Where | Why |
|---|---|---|
| 1. Generate SVG | Parent | Model judgment — composition, labels, semantic layout. Often delegates further to `visuals-claude`. |
| 2. Render + upload + share + post (combined) | **Sonnet sub-agent** | Pure shell + curl + one MCP call. Dropbox API JSON, ImageMagick stderr, and the Slack MCP result all stay out of the parent context. |
| 3. Print confirmation block | Parent | One ✓ line per pipeline step, taken verbatim from the agent's return. |

Use the `general-purpose` subagent type (the only one with both `*` tool access and a model override). Pass `model: "sonnet"`. The agent prompt embeds the full magick + curl + MCP recipe inline, so a human reading this skill still sees the canonical commands.

## Procedure

### 1. Generate the diagram as SVG

Use the `visuals-claude` skill's SVG-generation logic, or write the SVG directly if the diagram is simple. SVG is preferred over Mermaid because:
- No extra renderer dependency (Mermaid needs `mmdc` or headless Chrome)
- ImageMagick reads SVG natively
- Lossless output

Save to `$env:TEMP\share-diagram-<timestamp>.svg` (Windows) or `/tmp/share-diagram-<timestamp>.svg` (macOS/Linux). Use a UNIX timestamp to avoid collisions across invocations.

### 2. Hand off to a Sonnet sub-agent — it runs the rest of the pipeline

Spawn a `general-purpose` sub-agent with `model: "sonnet"`. The agent runs render → upload → share-link → `?raw=1` rewrite → Slack post, then returns an ordered set of `✓` lines that the parent prints in step 3.

**Channel ID:** use the user's Slack member ID (`U...`), not `@<bot_username>`. For Praveen in `T05MJ9YFFAN` use `U05MBLHE2J2`. Same convention as `slack-notify`.

**Worked example of the Agent call:**

````
Agent({
  subagent_type: "general-purpose",
  model: "sonnet",
  description: "Render SVG to PNG, upload to Dropbox, post inline to Slack",
  prompt: `
You are completing a diagram-sharing pipeline on behalf of the parent. The parent has already written an SVG to disk and chosen a caption. Your job: render it, host it, and post it inline to Slack. Run the steps in order — stop on first failure and report which step broke.

PAYLOAD (from parent):
- SVG path:    /tmp/share-diagram-1715444821.svg
- Slug:        boxes-and-arrows         (short alphanumeric+hyphens, ≤30 chars)
- Timestamp:   1715444821
- Caption:     🖼️  Boxes-and-arrows flow of A → B → C
- Channel ID:  U05MBLHE2J2

STEP A — Render SVG → PNG via ImageMagick
- PNG path: same directory as SVG, swap \`.svg\` for \`.png\`
- macOS/Linux:
    magick "<svg>" -density 200 -background white -alpha remove "<png>"
- Windows (binary lives at \`C:\\Program Files\\ImageMagick-*-Q16-HDRI\\magick.exe\`):
    & "C:\\Program Files\\ImageMagick-7.1.2-Q16-HDRI\\magick.exe" "<svg>" -density 200 -background white -alpha remove "<png>"
- \`-density 200\` oversamples for crisp text at Slack / phone sizes. \`-background white -alpha remove\` flattens transparency (Slack dark mode looks bad with transparent diagrams).
- If \`magick\` isn't found, stop and report: "ImageMagick not installed — install via \`winget install ImageMagick.ImageMagick\` / \`brew install imagemagick\` / \`apt install imagemagick\`".

STEP B — Upload to Dropbox
- Mint a token:
    TOKEN="$(~/.dropbox-token-fresh.sh 2>/dev/null || cat ~/.dropbox-token 2>/dev/null || echo "$DROPBOX_TOKEN")"
- Dropbox path: \`/share-diagram-<slug>-<ts>.png\`
- Upload:
    curl -sS -X POST https://content.dropboxapi.com/2/files/upload \\
      -H "Authorization: Bearer $TOKEN" \\
      -H 'Dropbox-API-Arg: {"path":"/share-diagram-<slug>-<ts>.png","mode":"overwrite","autorename":false,"mute":false}' \\
      -H 'Content-Type: application/octet-stream' \\
      --data-binary @"<png-path>"
- Parse the JSON response. Confirm \`path_display\` matches what you sent.
- On \`error\` field, stop and surface verbatim. Common cases: \`invalid_access_token\` → tell the user to regenerate at https://www.dropbox.com/developers/apps; \`path/conflict\` → pick a different name.
- App Folder permission type (most common): \`/foo.png\` is at \`Apps/<your-app-name>/foo.png\` from the user's perspective. Fine — they own the file.

STEP C — Create a public share link
- Command:
    curl -sS -X POST https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings \\
      -H "Authorization: Bearer $TOKEN" \\
      -H 'Content-Type: application/json' \\
      --data '{"path":"/share-diagram-<slug>-<ts>.png","settings":{"requested_visibility":"public"}}'
- Parse \`url\` field. Looks like \`https://www.dropbox.com/scl/fi/<id>/<filename>?rlkey=<key>&dl=0\`.
- If error \`shared_link_already_exists\`: extract the existing URL from the error payload (\`error.shared_link_already_exists.url\`) and reuse — do NOT crash, do NOT retry with a different path.

STEP D — Convert \`?dl=0\` → \`?raw=1\`
- Slack's image unfurl needs a URL that returns raw image bytes with \`Content-Type: image/...\`, not an HTML preview page. \`?dl=0\` returns HTML; \`?raw=1\` returns the file.
- Replace \`dl=0\` with \`raw=1\` in the URL. Final form:
    https://www.dropbox.com/scl/fi/<id>/<filename>?rlkey=<key>&raw=1

STEP E — Post to Slack
- Call mcp__slack__conversations_add_message with:
    channel_id:    <Channel ID from payload>
    content_type:  text/plain
    text:          <caption>\\n\\n<raw-url>
- The blank line between caption and URL is required — it keeps the URL standalone so Slack's link parser doesn't grab adjacent characters. \`text/plain\` avoids markdown-rendering surprises with the URL (see slack-notify's URL-format fix from commit 76db681).

RETURN exactly this structure, one line per step (✓ on success, ✗ + reason on failure):
  ✓ Rendered PNG: <bytes> bytes
  ✓ Uploaded to Dropbox: <path_display>
  ✓ Shared link: <dropbox-url-with-dl=0>
  ✓ Inline URL: <dropbox-url-with-raw=1>
  ✓ Slack: posted to <channel_id>

If any step fails, output the prior ✓ lines and a single ✗ line for the failing step. Do not retry. Do not silently skip steps. Do not post if any earlier step errored.
`
})
````

The agent inherits the parent's env, so `~/.dropbox-token-fresh.sh`, `magick`, `curl`, and the Slack MCP tool all resolve normally inside the sub-agent.

### 3. Print the agent's report

Prepend a leading `✓ Generated SVG: <path>` line (the agent doesn't know what the parent did before invoking it), then surface the agent's ordered lines verbatim. On any `✗` line, stop after printing — don't post a follow-up, don't retry. The user sees exactly which pipeline step broke.

## Edge cases

- **Token expired mid-pipeline.** Dropbox returns `invalid_access_token`. Stop, surface the regenerate URL (`https://www.dropbox.com/developers/apps`), do not retry blindly.
- **PNG too large for Dropbox unfurl.** Slack inline-renders images up to a few MB. If the PNG is over ~5 MB (large diagrams), reduce `-density` (try 150 or 100) and re-render.
- **Diagram has transparency and looks weird.** `-background white -alpha remove` is mandatory in the magick command — confirm it's there.
- **Same SVG already uploaded.** Reuse the existing share link via the `shared_link_already_exists` fallback.
- **User wants JPG.** Diagrams should be PNG (lossless, smaller for line art). Only switch to JPG if the user explicitly asks. JPG flag for magick: just change extension and add `-quality 85`.
- **User wants the file in a specific Dropbox folder.** Default path is `/share-diagram-<slug>-<ts>.png` at the app folder root. If the user wants a different folder, parameterize the path. Honor any user-given path; don't second-guess.

## Why this skill exists (design intent)

`slack-notify` solves "ping me with a clickable URL to come back to the session." It's the right primitive for status updates and decision-prompts.

`share-diagram` solves a different need: "I want the visual artifact itself **in Slack**, where my eyes already are, without leaving the chat." Use cases:
- Scrolling back through DM history later to find a sketch from earlier
- Sharing a diagram from your laptop to your phone screen-of-record
- Pinning a diagram in a Slack thread for reference

The choice of Dropbox over a third-party image host (imgur, GitHub gist, S3) is intentional: the user's own Dropbox account is private, owned by them, and doesn't leak diagrams to public services. Third-party hosts are fine for non-sensitive content but break the "your own infra" property.

PNG over JPG is also intentional: diagrams are line art with sharp text. JPG's lossy compression introduces artifacts on edges. PNG is the right format for this content type — full stop, unless the user explicitly overrides.
