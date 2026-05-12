
---

# Forge addendum (managed by ~/.claude-forge)

This section is appended by `install-project.sh`. Do not edit directly — re-run installer if it drifts.

## Required reading at session start

- `SESSION-STATE.md` (current state of work)
- `MISTAKES.md` (last 10 entries auto-injected by hook; full file at session start)
- `RISKY-PATHS.md` (paths requiring extra ceremony)
- `BORING.md` (paths requiring established patterns, not novel ones)

## Required skills by trigger

- Non-trivial code change → invoke `pre-flight-checklist` BEFORE first Edit
- Phase start (user says "let's start phase X") → invoke `premortem`
- Bug caught by user → invoke `bug-postmortem`
- Task end → invoke `definition-of-done`; for risky paths invoke `code-reviewer` subagent
- Session end / before compaction → invoke `session-debrief`

## Required hooks behavior

- `~/.claude/PAUSE_AND_REVIEW` exists → all tool calls blocked. Resume by deleting the file.
- Edit a file not Read this session → blocked. Read first.
- Claim "done" without test output in transcript → injected reminder.

## Refusal modes

When a hook blocks an action, do not retry the same action immediately. Read the rejection message, address the gap, then retry — or surface to the user that the gap can't be addressed and ask how to proceed.

## Push policy (override of Claude Code default)

The Claude Code default "DO NOT push to the remote repository unless the user explicitly asks" is **overridden** for this user. **Push freely after committing, including to `main`.** Treat push as the natural last step of commit — they are one operation.

**Reasons safe here:** Supabase migrations are applied manually (pushed migration code doesn't auto-run against prod DB), Vercel instant-rollback is one click + ~30 seconds, projects are pre-launch or low-blast-radius, and secret-file content hooks defend against the worst push mistake.

**Still confirm before:** `git push --force` / `--force-with-lease`, history-rewriting operations (rebase of pushed commits, `filter-repo`, BFG), or any push that triggers an irreversible side-effect (live payment keys flipped, prod-targeted webhooks armed, etc.). These are the cases where rollback is hard.

**Override scope:** this rule lives both here (project-level) and in `~/.claude/CLAUDE.md` (user-level) for redundancy. Either source is authoritative.

## Pre-push gate (before any `git push origin main`)

The user can't meaningfully evaluate diffs by reading them. The discipline lives in *Claude's* process — every row below must be green BEFORE pushing to `main`. Any red → push to a feature branch and surface what's uncertain. Honesty about "I shouldn't push this" IS the safety net.

1. **Build green** — project build command ran. Scan raw stdout for: `parallel pages`, `Module not found`, `Type error`, `Failed to compile`, `Cannot find module`. **Hook "Build passed" summaries have lied; trust only raw output.**
2. **Typecheck green** — workspace-wide typecheck (not just the package touched). Real stdout pasted.
3. **Tests green** — tests in modified packages run. If no test existed for the changed code path, ADD at least one regression test for the case just fixed.
4. **Diff self-read** — re-read the full `git diff origin/main..HEAD`. Looking for: missing `await`, `??` vs `||`, asymmetric reader/writer enforcement, missing helper swaps, off-by-one, leftover `console.log` / debug flags / hardcoded test data.
5. **Secret scan** — `git diff origin/main..HEAD` does NOT match: `sk_`, `pk_live_`, `xox[bpoa]-`, JWT-shaped strings, `BEGIN PRIVATE KEY`, `Bearer [A-Za-z0-9_-]{20,}`. Filename hooks miss secrets pasted inline into source files.
6. **UI changes hand-tested** — dev server started, golden path clicked, at least one edge case (empty / error / loading) verified, adjacent feature smoke-checked. OR explicit chat note: "couldn't browser-test because X."
7. **Risky-path workflow followed** — for any RISKY-PATHS.md match, `code-reviewer` subagent invoked, findings addressed or surfaced.
8. **Migration ordering** — schema changes applied to DB BEFORE pushing dependent code, schema-shape verified. Code depending on unapplied migration → branch tagged `BLOCKED ON MIGRATION N`, no main-push.
9. **Branch + commits sane** — current branch matches intent, diff shows only expected files, commit messages are real (not `WIP` / `fix` / `stuff`).
10. **Rollback plan articulated** — one sentence: "if this breaks, rollback is `git revert <sha> && git push`, impact is [scope]."

## Post-push (after `git push origin main`)

Stay attached. Watch the deploy URL. **Don't claim done until production is green.** If deploy fails, immediately revert (`git revert <sha> && git push`) — don't try to fix-forward under deploy pressure. Don't walk away mid-deploy.
