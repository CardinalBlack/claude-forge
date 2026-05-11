#!/usr/bin/env bash
# PreToolUse hook: before any `git commit` on main/master, shell out to
# Claude Haiku via the `claude` CLI to summarize the staged diff in plain
# English and print the summary to stderr. Layer 2 of the prompt-injection
# defense suite — pairs with Layer 1 (scan-commit-diff.sh) by giving the
# user a fast second-opinion read on what's about to ship to prod.
#
# Advisory only: never blocks. Worst case = no summary printed, commit
# proceeds normally. The user's eyeballs are the actual check.
#
# Gate (ALL must be true; otherwise silent exit 0):
#   1. tool_name == "Bash"
#   2. command matches `git commit` (whitespace/EOL after — avoid commit-tree)
#   3. current branch is `main` or `master`
#   4. `git diff --cached` is non-empty
#   5. `claude` CLI is on PATH
#   6. commit message does not contain `SKIP-SUMMARY:`
#
# Failure modes (all fail-open, exit 0):
#   - missing jq / malformed JSON / git failures / claude exits non-zero /
#     `timeout` not installed / claude hangs (timed out) / anything else
#
# Portability note: macOS does not ship `timeout`. If it's on PATH (e.g. via
# coreutils/gtimeout aliased) we use it; if not we run claude bare. Worst
# case on a stuck CLI is a slow commit — acceptable since this hook is
# explicitly advisory.
set -euo pipefail

PAYLOAD=$(cat -)

TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(jq -r '.tool_input.command // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Match `git commit` only (avoid commit-tree, commit-graph). Same regex as
# block-direct-main-commit.sh and scan-commit-diff.sh for consistency.
echo "$CMD" | grep -qE 'git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Override: SKIP-SUMMARY: anywhere in the command (typically in -m "...").
echo "$CMD" | grep -q 'SKIP-SUMMARY:' && exit 0

# Past this point any unexpected failure must not brick the commit.
set +e

# Gate 5: claude CLI present?
command -v claude >/dev/null 2>&1 || exit 0

# Gate 3: on main or master?
BRANCH=$(git branch --show-current 2>/dev/null)
BRANCH_RC=$?
[ $BRANCH_RC -ne 0 ] && exit 0
[ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ] || exit 0

# Gate 4: any staged diff?
DIFF=$(git diff --cached 2>/dev/null)
DIFF_RC=$?
[ $DIFF_RC -ne 0 ] && exit 0
[ -z "$DIFF" ] && exit 0

# Cap diff at ~12KB — Haiku context handles plenty more, but huge diffs
# waste tokens + slow the hook + dilute the summary. First 12K of a diff
# almost always covers the semantic shape of the change.
DIFF=$(printf '%s' "$DIFF" | head -c 12288)

PROMPT="Summarize this git diff in plain English in 2-3 sentences. Be specific about what files changed and what the semantic effect is. If there's anything unusual or risky (auth changes, new dependencies, deleted code, new external network calls, modified CI/CD, etc.), call it out explicitly. Diff follows:

$DIFF"

# Run claude with a timeout if available; otherwise run bare. We swallow
# stderr from claude itself so the user's terminal isn't polluted with
# CLI noise on failure — only the banner+summary on success is shown.
if command -v timeout >/dev/null 2>&1; then
    SUMMARY=$(timeout 30 claude --print --model haiku-4-5 "$PROMPT" 2>/dev/null)
    RC=$?
    # 124 = GNU timeout's "timed out" exit. Treat any non-zero as silent skip.
    [ $RC -ne 0 ] && exit 0
else
    SUMMARY=$(claude --print --model haiku-4-5 "$PROMPT" 2>/dev/null)
    RC=$?
    [ $RC -ne 0 ] && exit 0
fi

# Empty summary → nothing useful to show, skip silently.
[ -z "$SUMMARY" ] && exit 0

{
    echo "───── Pre-commit summary (Haiku) ─────"
    printf '%s\n' "$SUMMARY"
    echo "──────────────────────────────────────"
} >&2

exit 0
