# My Personal Skills

This folder contains user-level Claude Code skills I want to keep portable across machines.

Each subfolder is a self-contained skill (a `SKILL.md` plus any reference files it loads).

## Skills included

- **`skills/`** — the meta-skill invoked as `/skills`. Matches a task against the local awesome-claude-skills catalog, lets the user pick skill(s) via AskUserQuestion, then handles the original task using the selected skill(s).
- **`clean-code/`** — refactor or write code in the clean-code style of Jeffrey Way / Adam Wathan / Aaron Francis (Laracasts). Triggers on requests to refactor, simplify, or improve readability.

## Install on a new machine

Claude Code loads user-level skills from `~/.claude/skills/`. To install:

### Option 1 — ask Claude

Open Claude Code in this directory and say:

> Install the skills in `_my-skills/` to my user skills directory.

Claude should copy each subfolder of `_my-skills/` into `~/.claude/skills/` (preserving folder names), then confirm with `ls ~/.claude/skills/`.

### Option 2 — manual copy

**macOS / Linux:**
```bash
mkdir -p ~/.claude/skills
cp -r _my-skills/skills      ~/.claude/skills/
cp -r _my-skills/clean-code  ~/.claude/skills/
```

**Windows (Git Bash):**
```bash
mkdir -p ~/.claude/skills
cp -r _my-skills/skills      ~/.claude/skills/
cp -r _my-skills/clean-code  ~/.claude/skills/
```

**Windows (PowerShell):**
```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\skills" | Out-Null
Copy-Item -Recurse _my-skills\skills      "$env:USERPROFILE\.claude\skills\"
Copy-Item -Recurse _my-skills\clean-code  "$env:USERPROFILE\.claude\skills\"
```

After copying, restart Claude Code. The skills should appear in the available-skills list and be invocable as `/skills` and `/clean-code`.

## Verifying the install

Inside Claude Code, run `/skills` — if it loads, the meta-skill is wired up. For clean-code, ask Claude to "refactor this in the clean-code style" on any file.

## Updating

These copies are snapshots. To refresh from the live versions on this machine:

```bash
cp -r ~/.claude/skills/skills      _my-skills/
cp -r ~/.claude/skills/clean-code  _my-skills/
```

Then commit the diff.
