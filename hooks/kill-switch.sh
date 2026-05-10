#!/usr/bin/env bash
# PreToolUse hook: if ~/.claude/PAUSE_AND_REVIEW exists, refuse all tools.
# User creates the file with `touch ~/.claude/PAUSE_AND_REVIEW` to halt Claude
# mid-session; deletes it to resume. Optional: write a reason into the file
# and the hook surfaces it in the block message.
set -euo pipefail
if [ -f "$HOME/.claude/PAUSE_AND_REVIEW" ]; then
    REASON=$(cat "$HOME/.claude/PAUSE_AND_REVIEW" 2>/dev/null || echo "(no reason file content)")
    echo "BLOCKED: PAUSED by $HOME/.claude/PAUSE_AND_REVIEW. Reason: $REASON" >&2
    echo "To resume, delete the file. To set a reason, write it into the file before resuming." >&2
    exit 2
fi
exit 0
