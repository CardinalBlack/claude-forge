#!/usr/bin/env bash
# Drops the per-project bootstrap layer into a project repo: template .md
# files, PR template, ADR skeleton, CLAUDE.md addendum. Also registers the
# project for the daily-auditor.
#
# Idempotent: re-running never overwrites user-edited files or duplicates
# the CLAUDE.md addendum.
#
# Usage: install-project.sh [project_path]   (defaults to $(pwd))
set -euo pipefail

PROJECT="${1:-$(pwd)}"
BOOTSTRAP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$PROJECT" ]; then
    echo "error: $PROJECT is not a directory" >&2
    exit 1
fi

cd "$PROJECT"

# Per-project markdown templates. SESSION-STATE.md is a Task-4.8 addition
# beyond the original plan loop — without it, inject-session-state.sh has
# nothing to read in a fresh project.
for FILE in MISTAKES.md DEFINITION-OF-DONE.md RISKY-PATHS.md BORING.md SESSION-STATE.md; do
    if [ ! -f "$FILE" ]; then
        cp "${BOOTSTRAP_HOME}/templates/${FILE}" "$FILE"
        echo "created: $FILE"
    else
        echo "skip:    $FILE (already exists)"
    fi
done

# PR template.
mkdir -p .github
if [ ! -f .github/pull_request_template.md ]; then
    cp "${BOOTSTRAP_HOME}/templates/.github/pull_request_template.md" .github/pull_request_template.md
    echo "created: .github/pull_request_template.md"
fi

# ADR skeleton.
mkdir -p docs/adr
if [ ! -f docs/adr/0000-template.md ]; then
    cp "${BOOTSTRAP_HOME}/templates/adr/0000-template.md" docs/adr/0000-template.md
    echo "created: docs/adr/0000-template.md"
fi

# CLAUDE.md addendum: append to existing CLAUDE.md, or create if absent.
# The marker string is the idempotency check — re-running never duplicates.
ADDENDUM_MARKER="Bootstrap addendum (managed by ~/.claude-bootstrap)"
if [ -f CLAUDE.md ]; then
    if ! grep -qF "$ADDENDUM_MARKER" CLAUDE.md; then
        cat "${BOOTSTRAP_HOME}/templates/CLAUDE-ADDENDUM.md" >> CLAUDE.md
        echo "appended addendum to: CLAUDE.md"
    else
        echo "skip:    CLAUDE.md addendum (already present)"
    fi
else
    cp "${BOOTSTRAP_HOME}/templates/CLAUDE-ADDENDUM.md" CLAUDE.md
    echo "created: CLAUDE.md"
fi

# Register the project so the daily-auditor cron (Phase 6.1) finds it.
STATE_FILE="${HOME}/.claude/state/audited-projects.json"
mkdir -p "$(dirname "$STATE_FILE")"
[ -f "$STATE_FILE" ] || echo "[]" > "$STATE_FILE"
NAME=$(basename "$PROJECT")
TMP=$(mktemp)
jq --arg path "$PROJECT" --arg name "$NAME" '
  if any(.[]; .path == $path) then . else . + [{path:$path, name:$name}] end
' "$STATE_FILE" > "$TMP"
mv "$TMP" "$STATE_FILE"

echo "project layer installed in: $PROJECT"
