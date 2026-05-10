#!/usr/bin/env bash
# UserPromptSubmit hook: injects MISTAKES.md (last 10 entries) +
# DEFINITION-OF-DONE.md into Claude's per-turn context.
#
# CWD is the project root when Claude runs in a project. We look for the files
# in CWD; if neither exists, we no-op silently.
#
# NOTE: We drain stdin with `cat > /dev/null` even though we don't need the
# payload. UserPromptSubmit hooks receive a JSON payload on stdin; not draining
# it can cause SIGPIPE under some shells when the parent closes the pipe early.
# Defensive add beyond the original plan.
set -euo pipefail

# Drain stdin (Claude Code passes payload but we don't need it).
cat > /dev/null

MISTAKES=""
DOD=""

if [ -f "MISTAKES.md" ]; then
    # Last 10 bullet entries (lines starting with `- ` followed by indented continuations).
    MISTAKES=$(awk '
        /^- / {
            entries[++n] = $0
            cur = n
            next
        }
        cur { entries[cur] = entries[cur] "\n" $0 }
        END {
            start = (n > 10) ? n - 9 : 1
            for (i = start; i <= n; i++) print entries[i]
        }
    ' MISTAKES.md)
fi

if [ -f "DEFINITION-OF-DONE.md" ]; then
    DOD=$(cat DEFINITION-OF-DONE.md)
fi

[ -z "$MISTAKES" ] && [ -z "$DOD" ] && exit 0

CONTEXT="## Recent mistakes (do not repeat):

$MISTAKES

## Definition of done (apply to any task you call complete):

$DOD"

jq -nc --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $ctx
  }
}'
