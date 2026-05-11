#!/usr/bin/env bash
# Cron entrypoint: fires the daily-auditor subagent to run the weekly-audit
# skill across every project in ~/.claude/state/audited-projects.json.
# Writes per-project reports to <project>/reports/weekly/YYYY-Www.md and a
# cross-project digest to ~/.claude/reports/weekly-summary-YYYY-Www.md.
#
# Invoked by crontab Monday 07:00 (installed via scripts/install-crons.sh).
# Re-runnable manually; --dry-run for CI / smoke checks.
set -euo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

# ISO week format. Portable across BSD (macOS) and GNU date: both honor %G
# (ISO-week-numbering year) and %V (ISO week number, zero-padded). Using %G
# rather than %Y to avoid the late-December edge case where ISO week W01
# rolls into the next year.
WEEK=$(date +"%G-W%V")
REPORT_DIR="${HOME}/.claude/reports"
REPORT="${REPORT_DIR}/weekly-summary-${WEEK}.md"

mkdir -p "$REPORT_DIR"

if [ "$DRY_RUN" = "1" ]; then
    echo "would write: $REPORT"
    exit 0
fi

command -v claude >/dev/null || { echo "claude CLI not found on PATH" >&2; exit 1; }

PROMPT="Use the daily-auditor subagent to walk every project listed in ~/.claude/state/audited-projects.json. For each project, invoke the weekly-audit skill against that repo and save the per-project report to <project>/reports/weekly/${WEEK}.md. The weekly skill covers deeper-cadence items: ADR drift, mistakes-as-tests reconciliation, dependency staleness, model deprecations, BAA expiry, corpus freshness, CI green-bar trend. Aggregate cross-project red flags into a single summary at ${REPORT}."

claude --print "$PROMPT" >> "${REPORT}.log" 2>&1

echo "weekly audit complete: $REPORT"
