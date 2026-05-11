
---

# Bootstrap addendum (managed by ~/.claude-bootstrap)

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
- `git commit` on `main` → blocked. Use a feature branch.
- Edit a file not Read this session → blocked. Read first.
- Claim "done" without test output in transcript → injected reminder.

## Refusal modes

When a hook blocks an action, do not retry the same action immediately. Read the rejection message, address the gap, then retry — or surface to the user that the gap can't be addressed and ask how to proceed.
