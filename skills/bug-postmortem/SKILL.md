---
name: bug-postmortem
description: Invoke whenever the user catches a bug or wrong assumption. Produces a MISTAKES.md entry AND drafts the test / lint / hook that would have caught it.
---

# Bug Postmortem

Output two artifacts:

## 1) MISTAKES.md entry (append to MISTAKES.md)

```markdown
- **YYYY-MM-DD: <one-line summary>**
  - **What I assumed:** ...
  - **What was actually true:** ...
  - **How the bug manifested:** ...
  - **Root cause (one sentence):** ...
  - **What would have caught it earlier:** ...
  - **Test / lint / hook drafted:** ...
```

## 2) The actual test / lint / hook

Draft the smallest thing that, if it had existed before this bug, would have surfaced it. Examples:

- A unit test asserting the assumption you got wrong
- An ESLint rule for a pattern you reintroduced
- A pgTAP assertion for a schema invariant you violated
- A hook that refuses the action you took without verification

Write the file. Add it to the test suite or hook manifest. Run it. Confirm green.

Then commit BOTH the MISTAKES.md update AND the new test / lint / hook in a single commit with the message:

    chore(mistakes): add postmortem + regression guard for <one-line summary>
