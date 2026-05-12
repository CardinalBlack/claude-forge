# Definition of Done

A task is done when ALL of the following are true. If any row is NO, the task is not done.

| Check | Default required | Notes |
|---|---|---|
| Typecheck passes for every package the change touches | Yes | `pnpm -r typecheck` or per-package `tsc --noEmit` |
| Unit tests added or updated for the new behavior | Yes | If "no test possible", explain why |
| Tests pass | Yes | Paste the output |
| For UI changes: screenshot taken in real browser | Yes | Attach or link |
| For migrations: applied to a real DB, schema-shape integration test green | Yes | Don't trust dry-run only |
| For routes: hit with real HTTP request, response shape matches schema | Yes | curl + response paste |
| For external integration (Hermes, cron, MCP): smoke-tested end-to-end | Yes | Real environment, not just unit-mock |
| Diff self-reviewed for off-by-one, missing await, wrong operator | Yes | Re-read the diff, don't just write |
| All pre-flight assumptions verified | Yes | Cross-reference pre-flight-checklist |
| SESSION-STATE.md reflects this work | Yes | Update before claiming done |
| MISTAKES.md updated if any bug was caught during this task | Yes | Even small ones |
| code-reviewer subagent invoked for files in RISKY-PATHS.md | Yes (when risky path touched) | Report verdict |

## "I'd defer X" is NOT "done"

If you defer something to claim done, surface it explicitly. The user re-scopes, you don't.

## Additional gates before `git push origin main`

When the next action is pushing to `main` (which on most projects = a production deploy), the table above is necessary but not sufficient. ALL of these must also be green:

| Check | Default required | Notes |
|---|---|---|
| Build raw stdout scanned (not just hook summary) | Yes | Grep for `parallel pages`, `Module not found`, `Type error`, `Failed to compile`, `Cannot find module`. Hook summaries have lied. |
| Secret scan of `git diff origin/main..HEAD` clean | Yes | Patterns: `sk_`, `pk_live_`, `xox[bpoa]-`, JWT, `BEGIN PRIVATE KEY`, `Bearer [A-Za-z0-9_-]{20,}`. Inline secrets bypass filename hooks. |
| Migration applied to DB before code depending on it ships | Yes | OR branch tagged `BLOCKED ON MIGRATION N` and NO push to main. |
| Branch + diff sanity check | Yes | `git branch --show-current` correct; `git diff <base>..HEAD` shows only expected files; commit messages real. |
| Rollback plan in one sentence | Yes | "If this breaks, rollback is `git revert <sha> && git push`, impact is [scope]." |
| Stay attached for deploy | Yes (after push) | Watch deploy URL; if red, immediately `git revert <sha> && git push`. Don't fix-forward under deploy pressure. |

If any row is red OR you're uncertain: **push to a feature branch instead.** Honesty about "I shouldn't push this to main" IS the safety net.
