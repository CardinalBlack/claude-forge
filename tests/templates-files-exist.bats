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

@test "BORING.md template exists" {
    [ -f "$REPO_ROOT/templates/BORING.md" ]
    grep -q "^# Boring Paths" "$REPO_ROOT/templates/BORING.md"
}

@test "ADR template exists" {
    [ -f "$REPO_ROOT/templates/adr/0000-template.md" ]
    grep -q "^# ADR NNNN" "$REPO_ROOT/templates/adr/0000-template.md"
}

@test "PR template exists" {
    [ -f "$REPO_ROOT/templates/.github/pull_request_template.md" ]
    grep -q "^## What changed" "$REPO_ROOT/templates/.github/pull_request_template.md"
}

@test "CLAUDE-ADDENDUM.md template exists" {
    [ -f "$REPO_ROOT/templates/CLAUDE-ADDENDUM.md" ]
    grep -q "Forge addendum" "$REPO_ROOT/templates/CLAUDE-ADDENDUM.md"
}

@test "SESSION-STATE.md template exists with hook-required sections" {
    [ -f "$REPO_ROOT/templates/SESSION-STATE.md" ]
    grep -q "^# Session State" "$REPO_ROOT/templates/SESSION-STATE.md"
    # inject-session-state.sh greps for these three section headers; if a
    # template ships without them, every fresh project would silently no-op
    # the staleness-warning + state-injection hook.
    grep -q "^## In Progress" "$REPO_ROOT/templates/SESSION-STATE.md"
    grep -q "^## Next Up" "$REPO_ROOT/templates/SESSION-STATE.md"
    grep -q "^## Active Plan" "$REPO_ROOT/templates/SESSION-STATE.md"
}
