#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

@test "weekly-audit.sh exists and is executable" {
    [ -x "$REPO_ROOT/crons/weekly-audit.sh" ]
}

@test "weekly-audit.sh --dry-run emits expected report path with ISO week" {
    # ISO week format: YYYY-Www (e.g. 2026-W19).
    YEAR=$(date +%Y)
    run "$REPO_ROOT/crons/weekly-audit.sh" --dry-run
    [ "$status" -eq 0 ]
    [[ "$output" == *"$YEAR-W"* ]]
    [[ "$output" == *"weekly-summary"* ]]
}

@test "weekly-audit.sh --dry-run does not require the claude CLI" {
    run env PATH=/usr/bin:/bin "$REPO_ROOT/crons/weekly-audit.sh" --dry-run
    [ "$status" -eq 0 ]
}

@test "weekly-audit.sh creates reports directory on dry-run if missing" {
    TMP_HOME=$(mktemp -d)
    run env HOME="$TMP_HOME" "$REPO_ROOT/crons/weekly-audit.sh" --dry-run
    [ "$status" -eq 0 ]
    [ -d "$TMP_HOME/.claude/reports" ]
    rm -r "$TMP_HOME"
}
