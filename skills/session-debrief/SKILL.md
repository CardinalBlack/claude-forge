---
name: session-debrief
description: Invoke at session end (or when the user says "wrapping up", "let's stop here", or a PreCompact event fires). Updates SESSION-STATE.md, drains MISTAKES, surfaces unmet commitments.
---

# Session Debrief

Do these in order. Don't skip steps.

## 1. Update SESSION-STATE.md

- Bump "Last Updated" to today
- Move completed items from "In Progress" to "Recently Completed"
- Update "In Progress" with current actual state
- Update "Next Up" with what's queued
- If a phase completed, update "Active Plan" status

## 2. Append any new MISTAKES.md entries

Walk back through the session: any moment where you assumed wrong, the user corrected you, or a bug was caught? Each one gets a MISTAKES.md entry per the bug-postmortem skill format.

## 3. Surface unmet commitments

Walk back through the session: did you say "I'll write a test for that later" or "I'll come back and clean this up"? List any unmet commitments. Either complete them now or surface them as pending tasks.

## 4. Verify nothing is broken at HEAD

Run `git status` and `pnpm typecheck`. If either is unhappy, surface it before declaring debrief complete.

## 5. Commit the debrief

If SESSION-STATE.md or MISTAKES.md changed, commit them with:

    chore(session): debrief + state update

…on the current feature branch.
