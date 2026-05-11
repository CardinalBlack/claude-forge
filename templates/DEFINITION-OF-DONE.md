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
