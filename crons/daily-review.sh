#!/usr/bin/env bash
# Cron entrypoint: fires daily-auditor subagent across all projects in
# ~/.claude/state/audited-projects.json and writes a cross-project digest
# to ~/.claude/reports/daily-summary-YYYY-MM-DD.md.
#
# Invoked by crontab (installed via scripts/install-crons.sh) at 06:00
# local time daily. Re-runnable manually; --dry-run for CI / smoke checks.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

DATE=$(date +%Y-%m-%d)
REPORT_DIR="${HOME}/.claude/reports"
REPORT="${REPORT_DIR}/daily-summary-${DATE}.md"

mkdir -p "$REPORT_DIR"

if [ "$DRY_RUN" = "1" ]; then
    echo "would write: $REPORT"
    exit 0
fi

# Real run requires the Claude Code CLI on PATH. Plan's literal text used
# a `--agent <name>` flag, which doesn't exist in the actual CLI; the
# correct pattern is `claude --print "<prompt>"` with the agent identified
# in the prompt body (Claude Code's task-dispatch picks up the agent by
# description when the prompt names it).
command -v claude >/dev/null || { echo "claude CLI not found on PATH" >&2; exit 1; }

PROMPT="Use the daily-auditor subagent to walk every project listed in ~/.claude/state/audited-projects.json. For each project, invoke the daily-review skill against that repo's last 24h of activity and save the per-project report to <project>/reports/daily/${DATE}.md. Then aggregate red flags (test-suite shrinkage, repeat-mistakes in the same file, SESSION-STATE >24h stale, unverified done-claims, new high/critical CVEs) into a single cross-project summary at ${REPORT}."

claude --print "$PROMPT" >> "${REPORT}.log" 2>&1

echo "daily review complete: $REPORT"
