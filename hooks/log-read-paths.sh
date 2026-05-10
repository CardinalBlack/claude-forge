#!/usr/bin/env bash
# PostToolUse hook: appends the path Claude just Read to ${CLAUDE_READ_LOG}.
# Pairs with must-read-before-edit.sh, which checks membership.
set -euo pipefail
PAYLOAD=$(cat -)
TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ "$TOOL" = "Read" ] || exit 0
FILE=$(jq -r '.tool_input.file_path // .tool_input.filePath // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ -n "$FILE" ] || exit 0
LOG="${CLAUDE_READ_LOG:-$HOME/.claude/state/reads.log}"
mkdir -p "$(dirname "$LOG")"
echo "$FILE" >> "$LOG"
exit 0
