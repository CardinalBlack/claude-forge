---
name: definition-of-done
description: Invoke at the END of any non-trivial task to verify it actually meets the bar. Forces evidence-based confirmation rather than self-assessed "I think it works."
---

# Definition of Done

For any non-trivial task to be marked complete, output the following block, filling each row. Reject your own done-claim if any row says NO.

| Check | Status (YES / NO / N/A) | Evidence (command + output excerpt, OR explicit reason it doesn't apply) |
|---|---|---|
| Typecheck passes for every package touched | | |
| Unit tests added or updated for the new behavior | | |
| Tests pass | | |
| For UI changes: tested in real browser, screenshot taken | | |
| For migrations: applied locally, schema-shape integration test green | | |
| For routes: hit with a real HTTP request, response shape matches the schema | | |
| For Hermes plugin / cron / external integration: smoke-tested end-to-end | | |
| Diff reviewed by ME (not just written) for off-by-one, missing await, wrong operator | | |
| All assumptions from pre-flight-checklist have now been verified | | |
| SESSION-STATE.md updated to reflect this work | | |
| MISTAKES.md updated if any mistake was caught and fixed during this task | | |

If any row is NO, the task is not done. Either fix the gap or explicitly defer (with reason) and surface the gap to the user.
