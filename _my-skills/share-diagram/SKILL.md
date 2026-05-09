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

2. **Dropbox API token** — Required for the upload step. Read in this order:
   - Env var `DROPBOX_TOKEN` (preferred — set in shell or harness env)
   - File `~/.dropbox-token` (single-line, just the token string)
   
   If neither is found, do not silently fall back to ASCII or any third-party host. Stop and tell the user: *"No Dropbox token found. Put your token in `~/.dropbox-token` or set `DROPBOX_TOKEN` in your environment."* Optionally surface the create-token instructions: `https://www.dropbox.com/developers/apps` → your app → Settings → Generated access token.

   The token format is `sl.u.…` (Dropbox short-lived OAuth tokens). They expire after ~4 hours by default unless the app is configured for long-lived. If a Dropbox API call returns `invalid_access_token`, tell the user the token expired and link them to the regenerate page.

3. **ImageMagick installed** — needed to convert SVG → PNG. On Windows, the binary is at `C:\Program Files\ImageMagick-*-Q16-HDRI\magick.exe`. On macOS/Linux it's typically just `magick` on PATH.
   - Detect at the start of the procedure (try `magick --version` or look up the install path on Windows).
   - If missing, tell the user to install: Windows: `winget install ImageMagick.ImageMagick`; macOS: `brew install imagemagick`; Linux: `apt install imagemagick`.

## Procedure

### 1. Generate the diagram as SVG

Use the `visuals-claude` skill's SVG-generation logic, or write the SVG directly if the diagram is simple. SVG is preferred over Mermaid because:
- No extra renderer dependency (Mermaid needs `mmdc` or headless Chrome)
- ImageMagick reads SVG natively
- Lossless output

Save to `$env:TEMP\share-diagram-<timestamp>.svg` (Windows) or `/tmp/share-diagram-<timestamp>.svg` (macOS/Linux). Use a UNIX timestamp to avoid collisions across invocations.

### 2. Render SVG → PNG via ImageMagick

Windows (PowerShell), with a known install path:
```powershell
$magick = "C:\Program Files\ImageMagick-7.1.2-Q16-HDRI\magick.exe"  # adjust to actual install
& $magick "$env:TEMP\share-diagram-$ts.svg" -density 200 -background white -alpha remove "$env:TEMP\share-diagram-$ts.png"
```

The `-density 200` flag oversamples for crisp text at typical Slack/phone display sizes. `-background white -alpha remove` flattens any transparency to white (Slack's dark mode looks bad with transparent diagrams).

If the install path varies, find it once with:
```powershell
Get-ChildItem "$env:ProgramFiles" -Filter "magick.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
```

### 3. Upload to Dropbox

Path naming: use `/share-diagram-<short-slug>-<timestamp>.png`. The slug helps the user identify what each file is when they look in their Dropbox folder later. Keep the slug short (≤30 chars), alphanumeric with hyphens.

```bash
TOKEN="$(cat ~/.dropbox-token 2>/dev/null || echo "$DROPBOX_TOKEN")"
curl -sS -X POST https://content.dropboxapi.com/2/files/upload \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Dropbox-API-Arg: {"path":"/share-diagram-<slug>-<ts>.png","mode":"overwrite","autorename":false,"mute":false}' \
  -H 'Content-Type: application/octet-stream' \
  --data-binary @"<png-path>"
```

Parse the JSON response and confirm `path_display` matches what you sent. If the response has an `error` field, surface it to the user — common ones: `invalid_access_token` (regenerate), `path/conflict` (use `autorename:true` or pick a different name).

For App Folder permission type apps (most common), the Dropbox path is relative to the app's folder, not the user's Dropbox root. So `/foo.png` lives at `Apps/<your-app-name>/foo.png` from the user's perspective. This is fine — the user owns the file.

### 4. Create a public share link

```bash
curl -sS -X POST https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  --data '{"path":"/share-diagram-<slug>-<ts>.png","settings":{"requested_visibility":"public"}}'
```

Parse the `url` field — looks like `https://www.dropbox.com/scl/fi/<id>/<filename>?rlkey=<key>&dl=0`.

**If the file already has a shared link** (you uploaded the same path before), the API returns an error `shared_link_already_exists` with the existing URL. Catch that and reuse the existing URL — don't crash the skill.

### 5. Convert to inline-content URL for Slack

Slack's image unfurl needs a URL that returns raw image bytes with `Content-Type: image/...`, not an HTML preview page. Dropbox's default `?dl=0` returns HTML; `?raw=1` (or `?dl=1`) returns the file directly.

Replace `dl=0` with `raw=1` in the URL. Final form:
```
https://www.dropbox.com/scl/fi/<id>/<filename>?rlkey=<key>&raw=1
```

### 6. Post to Slack via the existing MCP tool

Call `mcp__slack__conversations_add_message`:

- `channel_id`: `@<bot-username>` (e.g. `@claude_mcp_praveen` for Crackle). Same convention as `slack-notify`.
- `content_type`: `text/plain` (avoids any markdown-rendering surprises with the URL — see slack-notify's URL-format fix from commit 76db681).
- `text`: a short caption + the inline-content URL on its own line. Format:

```
🖼️  <one-line caption describing the diagram>

<dropbox-raw-url>
```

The blank line between caption and URL is important — keeps the URL standalone so Slack's link parser doesn't grab adjacent characters.

### 7. Confirm in the local terminal

One short line per pipeline step:

- `✓ Generated SVG: <path>`
- `✓ Rendered PNG: <size> bytes`
- `✓ Uploaded to Dropbox: <path>`
- `✓ Shared link: <url>`
- `✓ Slack: posted to @<bot>`

If any step fails, surface the error and stop — don't post a broken link.

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
