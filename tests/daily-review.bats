#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

@test "daily-review.sh exists and is executable" {
    [ -x "$REPO_ROOT/crons/daily-review.sh" ]
}

@test "daily-review.sh --dry-run emits expected report path with today's date" {
    DATE=$(date +%Y-%m-%d)
    run "$REPO_ROOT/crons/daily-review.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"$DATE"* ]]
    [[ "$output" == *"daily-summary"* ]]
}

@test "daily-review.sh --dry-run does not require the claude CLI" {
    # Real cron-fire invokes claude; dry-run must short-circuit so the script
    # is testable in CI environments without claude installed.
    DATE=$(date +%Y-%m-%d)
    # Run with PATH stripped of claude to confirm the script doesn't try to
    # invoke it during --dry-run.
    run env PATH=/usr/bin:/bin "$REPO_ROOT/crons/daily-review.sh" --dry-run
    [ "$status" -eq 0 ]
}

@test "daily-review.sh creates reports directory on dry-run if missing" {
    # Idempotency / side-effect check: ensure the report dir is mkdir -p'd
    # even on dry-run so the actual cron-fire never errors on a missing dir.
    TMP_HOME=$(mktemp -d)
    run env HOME="$TMP_HOME" "$REPO_ROOT/crons/daily-review.sh" --dry-run
    [ "$status" -eq 0 ]
    [ -d "$TMP_HOME/.claude/reports" ]
    rm -r "$TMP_HOME"
}
