#!/usr/bin/env bash
# Installs project-local layer into <project>/. Run from any project root, or
# pass the project path as $1. Drops in template .md files; merges
# project-specific hooks; sets up CI workflow files.
set -euo pipefail

PROJECT="${1:-$(pwd)}"
BOOTSTRAP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Used by Phase 5 to copy from BOOTSTRAP_HOME/templates/* into the project.

# Phase 0 stub: empty placeholders for the smoke test. Phase 5 replaces this
# with actual cp from templates/.
touch "$PROJECT/MISTAKES.md"
touch "$PROJECT/DEFINITION-OF-DONE.md"
touch "$PROJECT/RISKY-PATHS.md"
