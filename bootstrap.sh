#!/usr/bin/env bash
# Installs the claude-bootstrap system into ~/.claude/.
# Idempotent: safe to re-run after `git pull`.
set -euo pipefail

CLAUDE_HOME="${HOME}/.claude"
BOOTSTRAP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "${CLAUDE_HOME}/skills"
mkdir -p "${CLAUDE_HOME}/agents"
mkdir -p "${CLAUDE_HOME}/state"
mkdir -p "${CLAUDE_HOME}/forensics"

# Merge hooks from MANIFEST.yaml into ~/.claude/settings.json. Idempotent —
# safe to re-run after `git pull` without duplicating entries or clobbering
# the user's hand-tuned config.
"${BOOTSTRAP_HOME}/scripts/install-hooks.sh"
