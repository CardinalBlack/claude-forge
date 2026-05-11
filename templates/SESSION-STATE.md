# Session State

**Last Updated:** YYYY-MM-DD

This file is read by `inject-session-state.sh` every turn. It injects the **In Progress**, **Next Up**, and **Active Plan** sections into Claude's context, and warns when the file's mtime is more than 24 hours old. Keep it current — the `session-debrief` skill is the canonical writer.

## Recently Completed
- (move items here from In Progress as they complete)

## In Progress
- (what's actively being worked on right now — include enough state for a fresh session to pick up)

## Next Up
- (queued but not started)

## Active Plan
- **Plan file:** (path to plan if one exists, e.g. `docs/plans/YYYY-MM-DD-foo.md`)
- **Status:** (which phases / tasks are done; what's next)

## Key Context
- (decisions, constraints, preferences established during the session that future-you would want to know)
