#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    # Test seam: install-crons.sh reads/writes this file instead of the
    # real `crontab -l/-` pair when CLAUDE_CRONTAB_FILE is set. Lets bats
    # exercise the merge logic safely without mutating the user's crontab.
    export CLAUDE_CRONTAB_FILE=$(mktemp)
}

teardown() {
    rm -f "$CLAUDE_CRONTAB_FILE" 2>/dev/null || true
}

@test "install-crons.sh exists and is executable" {
    [ -x "$REPO_ROOT/scripts/install-crons.sh" ]
}

@test "install-crons.sh adds daily-review and weekly-audit entries to empty crontab" {
    : > "$CLAUDE_CRONTAB_FILE"
    run "$REPO_ROOT/scripts/install-crons.sh"
    [ "$status" -eq 0 ]
    grep -q "daily-review.sh" "$CLAUDE_CRONTAB_FILE"
    grep -q "weekly-audit.sh" "$CLAUDE_CRONTAB_FILE"
    grep -q "claude-forge" "$CLAUDE_CRONTAB_FILE"
}

@test "install-crons.sh is idempotent — re-run does not duplicate entries" {
    : > "$CLAUDE_CRONTAB_FILE"
    "$REPO_ROOT/scripts/install-crons.sh"
    "$REPO_ROOT/scripts/install-crons.sh"
    "$REPO_ROOT/scripts/install-crons.sh"
    daily_count=$(grep -c "daily-review.sh" "$CLAUDE_CRONTAB_FILE")
    weekly_count=$(grep -c "weekly-audit.sh" "$CLAUDE_CRONTAB_FILE")
    [ "$daily_count" = "1" ]
    [ "$weekly_count" = "1" ]
}

@test "install-crons.sh preserves existing user crontab entries" {
    cat > "$CLAUDE_CRONTAB_FILE" <<'CRON'
# user's existing entry
0 3 * * * /usr/local/bin/backup-photos
*/15 * * * * curl -s https://example.com/healthcheck
CRON
    "$REPO_ROOT/scripts/install-crons.sh"
    grep -q "backup-photos" "$CLAUDE_CRONTAB_FILE"
    grep -q "healthcheck" "$CLAUDE_CRONTAB_FILE"
    grep -q "daily-review.sh" "$CLAUDE_CRONTAB_FILE"
}

@test "install-crons.sh writes cron entries pointing at this checkout's crons/ dir" {
    # Important: if the script hardcoded a path or symlinked elsewhere, the
    # user moving / renaming the bootstrap checkout would break the crons
    # silently. Confirm the entries reference $BOOTSTRAP_HOME/crons.
    : > "$CLAUDE_CRONTAB_FILE"
    "$REPO_ROOT/scripts/install-crons.sh"
    grep -qF "${REPO_ROOT}/crons/daily-review.sh" "$CLAUDE_CRONTAB_FILE"
    grep -qF "${REPO_ROOT}/crons/weekly-audit.sh" "$CLAUDE_CRONTAB_FILE"
}

@test "install-crons.sh emits 'crontab already current' on no-op re-run" {
    : > "$CLAUDE_CRONTAB_FILE"
    "$REPO_ROOT/scripts/install-crons.sh"
    run "$REPO_ROOT/scripts/install-crons.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"already current"* ]]
}
