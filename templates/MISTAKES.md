# MISTAKES — Don't Repeat

This file is auto-injected into Claude's context every turn (last 10 entries). Add to it via the bug-postmortem skill whenever a bug is caught or an assumption is wrong.

## How to add an entry

When the user catches a bug or corrects an assumption:
1. Invoke the `bug-postmortem` skill.
2. Append the entry below in the format shown.
3. Draft the corresponding test / lint / hook that would have caught it.
4. Commit both in one commit.

## Format

- **YYYY-MM-DD: <one-line summary>**
  - **What I assumed:**
  - **What was actually true:**
  - **How the bug manifested:**
  - **Root cause:**
  - **What would have caught it earlier:**
  - **Test / lint / hook drafted:**

## Entries

(none yet)
