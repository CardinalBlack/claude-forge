#!/usr/bin/env bash
# PreToolUse hook: refuses to let Claude Edit a file it hasn't Read in this
# session. Allowed for Write to non-existing paths (creating new files).
#
# State is per-session: the SessionStart hook truncates ${CLAUDE_READ_LOG}.
# The PostToolUse hook for Read appends the path to it. This hook checks
# membership.
set -euo pipefail

PAYLOAD=$(cat -)
TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD")
FILE=$(jq -r '.tool_input.file_path // .tool_input.filePath // empty' <<< "$PAYLOAD")

# Only act on Edit. Write to a non-existing file is creation; allow it.
[ "$TOOL" = "Edit" ] || exit 0
[ -n "$FILE" ] || exit 0

LOG="${CLAUDE_READ_LOG:-$HOME/.claude/state/reads.log}"

# If the log doesn't exist yet, fail-open (first session may not have one).
[ -f "$LOG" ] || exit 0

if grep -qxF "$FILE" "$LOG"; then
    exit 0
fi

# Some Edits to files-Claude-just-created will not show in the read log;
# allow if file mtime is within the last 60s (assume Claude created it).
if [ -f "$FILE" ]; then
    if [ "$(($(date +%s) - $(stat -f %m "$FILE" 2>/dev/null || stat -c %Y "$FILE" 2>/dev/null || echo 0)))" -lt 60 ]; then
        exit 0
    fi
fi

echo "BLOCKED: read $FILE before editing. (Override: re-Read the file or set CLAUDE_BYPASS_READ_CHECK=1.)" >&2
[ "${CLAUDE_BYPASS_READ_CHECK:-}" = "1" ] && exit 0
exit 2
