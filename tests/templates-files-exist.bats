#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

@test "MISTAKES.md template exists" {
    [ -f "$REPO_ROOT/templates/MISTAKES.md" ]
    grep -q "^# MISTAKES" "$REPO_ROOT/templates/MISTAKES.md"
}

@test "DEFINITION-OF-DONE.md template exists" {
    [ -f "$REPO_ROOT/templates/DEFINITION-OF-DONE.md" ]
    grep -q "^# Definition of Done" "$REPO_ROOT/templates/DEFINITION-OF-DONE.md"
}

@test "RISKY-PATHS.md template exists" {
    [ -f "$REPO_ROOT/templates/RISKY-PATHS.md" ]
    grep -q "^# Risky Paths" "$REPO_ROOT/templates/RISKY-PATHS.md"
}
