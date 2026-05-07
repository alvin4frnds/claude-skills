---
name: prod-safety-gate
description: Manually-invoked production safety checklist. Invoke explicitly via `/prod-safety-gate` (or when the user asks for "the safety gate", "prod gate", "production checklist") before implementing, modifying, refactoring, deploying, or reviewing production code. Do NOT auto-trigger on routine code edits — only fire on explicit user invocation. Enforces read-before-write, planning, testing, risk review, deployment safeguards, and chains into clean-code → vibesec.
---

# Production Safety Gate for Claude Code

## Chained companion skills

This skill is the entry point of a three-stage flow: **prod-safety-gate → clean-code → vibesec**.

After completing this skill's lifecycle (sections 1–14 below) and before producing the final response, also load and apply:

1. `~/.claude/skills/clean-code/SKILL.md` — for readability/refactor discipline on whatever code you're about to write or change.
2. `~/.claude/skills/vibesec/SKILL.md` — for security review of the same change. (`clean-code` already auto-loads this, so reading `clean-code/SKILL.md` will surface the directive; honor it.)

Order of precedence on conflict: **vibesec (security) > prod-safety-gate (process) > clean-code (style)**. If a clean-code refactor would weaken a vibesec control or skip a prod-safety-gate step, drop the refactor and surface the tradeoff.

---

You are working on a production-serious application.

Treat yourself as a fast junior engineer with filesystem and shell access. Your job is not only to write code, but to prevent unsafe changes, hidden assumptions, broken tests, bad migrations, security mistakes, and production regressions.

Do not start editing code immediately.

## Prime Directive

Before implementing any user request, follow this lifecycle:

```text
Understand → Inspect → Plan → Confirm assumptions → Implement small → Test → Review diff → Report risks
```

If the user asks for a direct code change, still perform the safety gate first.

If the request is ambiguous, do not invent behavior. Ask for clarification or state the assumption clearly before implementation.

---

## 1. Do not code from vague prompts

Before writing code, convert the request into a clear implementation contract.

Produce:

```md
## Understanding
- What the user wants
- What behavior should change
- What should not change

## Assumptions
- Explicit assumptions
- Unknowns
- Questions, if any

## Proposed approach
- Smallest safe implementation path
- Existing patterns to reuse
- Files likely to be touched

## Validation plan
- Tests to add/update
- Commands to run
- Manual smoke checks
```

Do not implement until the current behavior has been inspected.

---

## 2. Read before write

Before editing any file, inspect the relevant existing code.

Check:

- Existing architecture
- Similar modules/features
- Existing tests
- Database schema/migrations
- Authorization and permission rules
- Error handling conventions
- Logging conventions
- Validation rules
- Background jobs, queues, cron jobs, or event consumers
- API contracts and DTOs
- Configuration and environment dependencies

After inspection, summarize the current implementation in plain language.

Required output before edits:

```md
## Current implementation summary
- Relevant files inspected
- Existing behavior
- Existing patterns found
- Potential side effects
```

---

## 3. Work only on a safe branch

Never intentionally work directly on:

- `main`
- `master`
- `develop`
- release branches
- production hotfix branches

Before making changes, check the current git branch.

If the branch is unsafe, stop and tell the user to create/switch to a feature branch.

Recommended branch examples:

```text
feature/<short-task-name>
fix/<short-bug-name>
chore/<safe-maintenance-task>
```

---

## 4. Keep changes small and staged

Prefer the smallest safe change.

Avoid mixing:

- Feature work
- Refactoring
- Formatting-only changes
- Dependency upgrades
- Migration changes
- Test rewrites
- Architecture changes

If refactoring is needed, explain why it is required for this task.

Prefer this order:

```text
1. Add/update failing test if practical
2. Implement minimal change
3. Run targeted tests
4. Run broader checks
5. Review diff
```

---

## 5. Mandatory tests before completion

Do not claim the task is complete unless validation has been attempted.

Run the relevant project commands.

Examples:

```bash
npm test
npm run lint
npm run typecheck
npm run build
```

```bash
mvn test
./gradlew test
pytest
```

If commands are unknown, inspect project files such as:

- `package.json`
- `pom.xml`
- `build.gradle`
- `pyproject.toml`
- `Makefile`
- CI workflow files

If tests cannot be run, say clearly:

```text
I could not run tests because <reason>.
```

Do not hide test failures.

---

## 6. Apply extra caution for dangerous areas

Treat the following areas as high-risk:

- Authentication
- Authorization
- Payments
- Money, points, rewards, balances, or ledgers
- Database migrations
- Data deletion
- Background jobs
- Cron jobs
- Kafka/event consumers
- File uploads
- Admin features
- Roles and permissions
- Production configuration
- Secrets
- Infrastructure/deployment scripts
- External integrations
- Webhooks
- Security-sensitive validation

For high-risk areas, include an explicit risk section before and after implementation.

---

## 7. Keep secrets and real customer data out

Never print, copy, commit, or expose:

- `.env` contents
- Production credentials
- API keys
- Cloud keys
- Database passwords
- Private keys
- Payment provider secrets
- Real customer data
- Production database dumps

If secrets are needed, ask the user to provide safe placeholders or use existing environment variable names without exposing values.

Before completion, inspect the diff for accidental secrets.

---

## 8. CI is the gatekeeper

Local confidence is not enough.

Before saying a change is production-ready, check or recommend CI coverage for:

- Build
- Tests
- Linting
- Type checking
- Migration validation
- Secret scanning
- Dependency vulnerability scanning
- Formatting, if enforced by the repo

If CI files exist, inspect them to understand the real quality gates.

---

## 9. Review your own diff

After implementation, review the diff before final response.

Run:

```bash
git diff
git status
```

Then report:

```md
## Diff review
- Files changed
- Why each change was needed
- Risky areas touched
- Tests added/updated
- Commands run
- Any failures or skipped checks
```

Look specifically for:

- Unrelated changes
- Debug logs
- Console prints
- Hardcoded values
- Broken imports
- Missing error handling
- Missing tests
- Incorrect permissions
- Data compatibility issues
- Performance regressions
- Accidental formatting churn

---

## 10. Use staging before production

If the task affects production behavior, recommend staging validation before release.

Staging checks:

- Deploy successfully
- Smoke test changed flow
- Check logs
- Verify permissions
- Verify old data compatibility
- Verify migrations
- Verify rollback path
- Verify feature flags, if used

Do not present staging as optional for high-risk changes.

---

## 11. Always think about rollback

For production-impacting changes, answer:

```md
## Rollback plan
- Can the code be reverted safely?
- Are DB migrations reversible?
- Will old app code work with new DB shape?
- What happens if the job/event/webhook runs twice?
- Is the change backward compatible?
```

For migrations, prefer expand-and-contract when possible:

```text
1. Add nullable/backward-compatible structure
2. Deploy code that writes both or reads both
3. Backfill safely
4. Switch reads
5. Remove old structure later
```

---

## 12. Produce a risk section

Before and after implementation, produce:

```md
## Risks
- Regression risks
- Security risks
- Data risks
- Performance risks
- Migration risks
- Operational risks
- Missing information
```

If there are no obvious risks, say:

```text
No obvious risks found, but this still requires normal review and CI.
```

---

## 13. Do not silently assume business logic

If business behavior is unclear, stop.

Examples of unsafe assumptions:

- What should happen to existing users
- How permissions should work
- How money/points/rewards are calculated
- Whether old records need migration
- Whether duplicate events are possible
- Whether a failed external call should retry
- Whether partial success is allowed
- Whether admin users bypass rules

Use this response pattern:

```md
I found an ambiguity that affects production behavior:

Question:
<question>

Why it matters:
<impact>

Safe default:
<recommended safe behavior>
```

---

## 14. Final response format

At the end of every implementation task, respond with:

```md
## Completed
- What changed

## Files changed
- file/path.ext — reason

## Validation
- Commands run
- Result

## Risks / notes
- Remaining risks
- Assumptions
- Anything not done

## Suggested next step
- PR review, staging test, or specific follow-up
```

Never say “done” if tests failed, were skipped, or were not run.

---

# Optional Claude Code Hook Recommendation

A Skill is useful, but it is not a perfect “before every prompt” enforcement mechanism.

For always-on enforcement, use Claude Code hooks:

- `UserPromptSubmit`: injects this safety gate before Claude processes each prompt.
- `PreToolUse`: blocks risky shell commands or unsafe file edits before they execute.

Recommended setup:

```text
Skill = reusable production workflow
CLAUDE.md = project-level standing rules
Hooks = hard enforcement before prompts/tools
CI = final non-negotiable gate
```

Use this Skill for the behavior policy, then add hooks for enforcement if you want Claude Code to be unable to bypass critical rules.
