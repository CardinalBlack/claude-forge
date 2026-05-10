#!/usr/bin/env bash
# Stop hook: when Claude's last message claims "done" but no verification
# (typecheck / test run) appears in the recent transcript, inject a reminder
# urging a real run before claiming complete.
#
# Why this exists: the user has been burned repeatedly by Claude declaring
# work done without running tsc/tests. This hook nudges (but does not block)
# at the Stop event, which fires after a turn finishes.
#
# Detection is intentionally cheap: substring grep against the tail of the
# transcript JSONL. We do NOT parse JSON-Lines — the transcript is messy and
# any matched substring in the recent window is good enough signal.
#
# Fail-open everywhere: bad JSON, missing jq, unreadable transcript → exit 0.
# A nag hook that bricks the session is worse than one that misses an edge.
set -euo pipefail

PAYLOAD=$(cat -)

# Fail-open on malformed JSON.
TRANSCRIPT=$(jq -r '.transcript_path // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || exit 0

# Last ~1KB ≈ the most recent assistant text. Look for done-claim markers.
LAST_ASSISTANT=$(tail -c 1024 "$TRANSCRIPT" 2>/dev/null) || exit 0
echo "$LAST_ASSISTANT" | grep -qiE 'all done|complete|verified|fixed|ready to|passes(\.|!|$)|tests pass' || exit 0

# Last ~8KB ≈ recent activity window. Look for verification markers.
# Note: the "tests ... passed" branch uses [^[:cntrl:]]* (POSIX class, BSD-grep
# safe — \s would not be) to span common test-runner output like
# "Test Files  22 passed (22)" or "Tests  314 passed (314)". Bounded to a
# single line because newline is a control char, so the match can't run away.
TAIL=$(tail -c 8192 "$TRANSCRIPT" 2>/dev/null) || exit 0
if echo "$TAIL" | grep -qiE 'tests?[^[:cntrl:]]*(passed|pass)|✓ tests|noEmit|typecheck|tsc.*--noEmit|vitest|jest|pytest'; then
    exit 0
fi

CONTEXT="WARNING: You appear to be wrapping up but I see no verification output in the recent transcript. Before claiming done, run:

    pnpm typecheck && pnpm test

…or the equivalent for this stack, and paste the output. If you've already verified, restate the command + output for the record."

jq -nc --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "Stop",
    additionalContext: $ctx
  }
}'
