#!/usr/bin/env bash
# PreToolUse hook: refuses `git commit` on main/master unless explicitly
# overridden. Most catastrophic regressions ship via direct commits to the
# default branch — forcing a feature branch is the single biggest blast-radius
# reducer.
#
# Allow conditions (any one):
#   1. Tool is not Bash (silent exit 0).
#   2. Command is not `git commit` (silent exit 0). The match is tightened to
#      avoid false positives on `git commit-tree` and `git commit-graph`.
#   3. CLAUDE_ALLOW_MAIN=1 in env.
#   4. Command contains the literal string "ALLOW-MAIN-COMMIT:" (intended for
#      use inside the commit message itself).
#   5. Current branch is neither `main` nor `master` (incl. detached HEAD or
#      not-in-a-repo: branch is empty string, not main/master).
#
# Otherwise: exit 2 with a stderr explanation.
set -euo pipefail

PAYLOAD=$(cat -)

# Fail-open on malformed JSON: a hook that bricks Claude Code on bad input
# is worse than one that misses an edge case.
TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(jq -r '.tool_input.command // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Tightened: require whitespace-or-EOL after "commit" so we don't match
# `git commit-tree` or `git commit-graph` (different plumbing commands).
echo "$CMD" | grep -qE 'git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Overrides.
[ "${CLAUDE_ALLOW_MAIN:-}" = "1" ] && exit 0
echo "$CMD" | grep -q "ALLOW-MAIN-COMMIT:" && exit 0

BRANCH=$(git branch --show-current 2>/dev/null || echo "")
[ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ] || exit 0

cat >&2 <<MSG
BLOCKED: cannot commit directly to main. Create a feature branch:

    git checkout -b feat/<short-name>

Then retry the commit. Override (use sparingly): include ALLOW-MAIN-COMMIT: <reason> in the commit message, or set CLAUDE_ALLOW_MAIN=1.
MSG
exit 2
