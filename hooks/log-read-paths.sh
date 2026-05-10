#!/usr/bin/env bash
set -euo pipefail
PAYLOAD=$(cat -)
TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD")
[ "$TOOL" = "Read" ] || exit 0
FILE=$(jq -r '.tool_input.file_path // .tool_input.filePath // empty' <<< "$PAYLOAD")
[ -n "$FILE" ] || exit 0
LOG="${CLAUDE_READ_LOG:-$HOME/.claude/state/reads.log}"
mkdir -p "$(dirname "$LOG")"
echo "$FILE" >> "$LOG"
exit 0
