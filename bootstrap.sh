#!/usr/bin/env bash
# claude-forge installer.
# Installs skills, agents, hooks, and (when shipped) crons into ~/.claude/.
# Idempotent: safe to re-run after `git pull`.
#
# Skills + agents are SYMLINKED, not copied, so `git pull` in this repo
# updates them automatically. Settings.json hook entries are merged via
# scripts/install-hooks.sh (idempotent, preserves user hooks).
set -euo pipefail

CLAUDE_HOME="${HOME}/.claude"
BOOTSTRAP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${CLAUDE_HOME}/skills"
mkdir -p "${CLAUDE_HOME}/agents"
mkdir -p "${CLAUDE_HOME}/state"
mkdir -p "${CLAUDE_HOME}/forensics"
mkdir -p "${CLAUDE_HOME}/reports"

# Symlink skills. If the target is an existing symlink (ours or stale) or
# absent, replace/create it with -sfn. If the target is a real directory the
# user has placed there (e.g. their own hand-curated skill of the same name),
# refuse to clobber — warn and skip.
for SKILL in "${BOOTSTRAP_HOME}/skills"/*/; do
    NAME=$(basename "$SKILL")
    LINK="${CLAUDE_HOME}/skills/${NAME}"
    if [ -L "$LINK" ] || [ ! -e "$LINK" ]; then
        ln -sfn "$SKILL" "$LINK"
    elif [ -d "$LINK" ] && [ ! -L "$LINK" ]; then
        echo "skip: ${LINK} exists as a real directory; remove it manually if you want to use the bootstrap version" >&2
    fi
done

# Symlink agents (same logic but flat files, not directories).
for AGENT in "${BOOTSTRAP_HOME}/agents"/*.md; do
    NAME=$(basename "$AGENT")
    LINK="${CLAUDE_HOME}/agents/${NAME}"
    if [ -L "$LINK" ] || [ ! -e "$LINK" ]; then
        ln -sfn "$AGENT" "$LINK"
    fi
done

# Merge hooks from MANIFEST.yaml into ~/.claude/settings.json.
"${BOOTSTRAP_HOME}/scripts/install-hooks.sh"

# Install crons (Phase 6). Conditional so Phase 5 ships independently —
# bootstrap.sh remains green when this script doesn't exist yet.
if [ -x "${BOOTSTRAP_HOME}/scripts/install-crons.sh" ]; then
    "${BOOTSTRAP_HOME}/scripts/install-crons.sh"
fi

SKILL_COUNT=$(ls "${CLAUDE_HOME}/skills" 2>/dev/null | wc -l | tr -d ' ')
AGENT_COUNT=$(ls "${CLAUDE_HOME}/agents" 2>/dev/null | wc -l | tr -d ' ')

echo "claude-forge installed."
echo "  skills: ${SKILL_COUNT}"
echo "  agents: ${AGENT_COUNT}"
echo "  hooks merged into ${CLAUDE_HOME}/settings.json"
