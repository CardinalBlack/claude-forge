#!/usr/bin/env bash
# Adds the daily-review and weekly-audit cron entries to the user's
# crontab. Idempotent: re-running never duplicates entries; existing
# user-owned entries are preserved.
#
# Cron schedule:
#   daily-review.sh   — 06:00 every day
#   weekly-audit.sh   — 07:00 every Monday
#
# Test seam: when CLAUDE_CRONTAB_FILE is set, this script reads/writes
# that file instead of invoking `crontab -l` / `crontab -`. This lets the
# bats suite exercise the merge logic without mutating the user's actual
# crontab. In normal use the env var is unset and the script behaves as
# documented.
set -euo pipefail

BOOTSTRAP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

DAILY_CMD="${BOOTSTRAP_HOME}/crons/daily-review.sh"
WEEKLY_CMD="${BOOTSTRAP_HOME}/crons/weekly-audit.sh"

DAILY_LINE="0 6 * * * ${DAILY_CMD} > /tmp/claude-daily-review.log 2>&1  # claude-bootstrap"
WEEKLY_LINE="0 7 * * 1 ${WEEKLY_CMD} > /tmp/claude-weekly-audit.log 2>&1  # claude-bootstrap"

# Read current crontab (or test-seam file if set).
read_current() {
    if [ -n "${CLAUDE_CRONTAB_FILE:-}" ]; then
        cat "${CLAUDE_CRONTAB_FILE}" 2>/dev/null || echo ""
    else
        crontab -l 2>/dev/null || echo ""
    fi
}

# Write new crontab (or test-seam file).
write_new() {
    if [ -n "${CLAUDE_CRONTAB_FILE:-}" ]; then
        cat > "${CLAUDE_CRONTAB_FILE}"
    else
        crontab -
    fi
}

CURRENT=$(read_current)
NEW="$CURRENT"

# Idempotency: match by the daily/weekly command path string. Matching on
# the comment ("# claude-bootstrap") alone would re-add lines if the user
# moves/renames the bootstrap checkout. Matching the absolute command path
# means moving the checkout requires a re-install (correct behavior — the
# old paths in crontab would silently 404 otherwise).
if ! echo "$CURRENT" | grep -qF "$DAILY_CMD"; then
    NEW=$(printf "%s\n%s" "$NEW" "$DAILY_LINE")
fi
if ! echo "$CURRENT" | grep -qF "$WEEKLY_CMD"; then
    NEW=$(printf "%s\n%s" "$NEW" "$WEEKLY_LINE")
fi

if [ "$NEW" != "$CURRENT" ]; then
    # Strip the leading empty line that the printf "%s\n%s" with empty
    # $NEW would introduce on a fresh crontab.
    echo "$NEW" | sed '/./,$!d' | write_new
    echo "crontab updated"
else
    echo "crontab already current"
fi
