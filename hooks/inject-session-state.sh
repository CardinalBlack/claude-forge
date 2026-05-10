#!/usr/bin/env bash
# UserPromptSubmit hook: injects SESSION-STATE.md sections (In Progress / Next
# Up / Active Plan) into Claude's per-turn context. Warns if SESSION-STATE.md
# hasn't been updated in over 24 hours.
#
# NOTE: We drain stdin with `cat > /dev/null` even though we don't need the
# payload. UserPromptSubmit hooks receive a JSON payload on stdin; not draining
# it can cause SIGPIPE under some shells when the parent closes the pipe early.
# Defensive add beyond the original plan.
set -euo pipefail

# Drain stdin (Claude Code passes payload but we don't need it).
cat > /dev/null

[ -f "SESSION-STATE.md" ] || exit 0

# Slice "In Progress" + "Next Up" + "Active Plan" sections.
SECTIONS=$(awk '
    /^## (In Progress|Next Up|Active Plan)/ { capture=1; print; next }
    /^## / && !/^## (In Progress|Next Up|Active Plan)/ { capture=0 }
    capture
' SESSION-STATE.md)

# Staleness check: portable mtime via stat (BSD `-f %m` first, GNU `-c %Y` fallback).
NOW=$(date +%s)
MTIME=$(stat -f %m SESSION-STATE.md 2>/dev/null || stat -c %Y SESSION-STATE.md)
AGE_HOURS=$(( (NOW - MTIME) / 3600 ))

STALE=""
if [ "$AGE_HOURS" -gt 24 ]; then
    STALE="

WARNING: SESSION-STATE.md is STALE (last updated ${AGE_HOURS}h ago). Per global rule, refresh it before resuming non-trivial work."
fi

CONTEXT="## Current SESSION-STATE.md:

$SECTIONS$STALE"

jq -nc --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
