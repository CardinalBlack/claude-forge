#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export TEST_HOME=$(mktemp -d)
    export REAL_HOME="$HOME"
    export HOME="$TEST_HOME"
    export TEST_PROJECT=$(mktemp -d)
    cd "$TEST_PROJECT"
    git init -q -b main
}

teardown() {
    export HOME="$REAL_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
    rm -r "$TEST_PROJECT" 2>/dev/null || true
}

@test "install-project.sh creates MISTAKES.md" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/MISTAKES.md" ]
}

@test "install-project.sh creates DEFINITION-OF-DONE.md" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/DEFINITION-OF-DONE.md" ]
}

@test "install-project.sh creates RISKY-PATHS.md" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/RISKY-PATHS.md" ]
}

@test "install-project.sh creates BORING.md" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/BORING.md" ]
}

@test "install-project.sh creates SESSION-STATE.md" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/SESSION-STATE.md" ]
    # Hook-required sections must survive the copy.
    grep -q "^## In Progress" "$TEST_PROJECT/SESSION-STATE.md"
    grep -q "^## Next Up" "$TEST_PROJECT/SESSION-STATE.md"
    grep -q "^## Active Plan" "$TEST_PROJECT/SESSION-STATE.md"
}

@test "install-project.sh copies the actual template contents, not empty stubs" {
    # Phase 0 stub used `touch`; Phase 5 must cp from templates/. Assert
    # one substantive marker per template so a regression to touch-stubs
    # shows up here, not at the user's first prompt-submit.
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    grep -q "^# MISTAKES" "$TEST_PROJECT/MISTAKES.md"
    grep -q "^# Definition of Done" "$TEST_PROJECT/DEFINITION-OF-DONE.md"
    grep -q "^# Risky Paths" "$TEST_PROJECT/RISKY-PATHS.md"
    grep -q "^# Boring Paths" "$TEST_PROJECT/BORING.md"
}

@test "install-project.sh creates .github/pull_request_template.md" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/.github/pull_request_template.md" ]
    grep -q "^## What changed" "$TEST_PROJECT/.github/pull_request_template.md"
}

@test "install-project.sh creates docs/adr/0000-template.md" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/docs/adr/0000-template.md" ]
}

@test "install-project.sh creates CLAUDE.md when absent" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/CLAUDE.md" ]
    grep -q "Forge addendum" "$TEST_PROJECT/CLAUDE.md"
}

@test "install-project.sh appends addendum to existing CLAUDE.md, doesn't overwrite" {
    echo "# My project's CLAUDE.md" > "$TEST_PROJECT/CLAUDE.md"
    echo "User-owned content that must survive." >> "$TEST_PROJECT/CLAUDE.md"
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    grep -q "User-owned content that must survive" "$TEST_PROJECT/CLAUDE.md"
    grep -q "Forge addendum" "$TEST_PROJECT/CLAUDE.md"
}

@test "install-project.sh is idempotent — re-run does not duplicate addendum" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    count=$(grep -c "Forge addendum" "$TEST_PROJECT/CLAUDE.md")
    [ "$count" = "1" ]
}

@test "install-project.sh registers project in audited-projects.json" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_HOME/.claude/state/audited-projects.json" ]
    # jq parses cleanly, project path present.
    jq -e --arg p "$TEST_PROJECT" 'any(.[]; .path == $p)' "$TEST_HOME/.claude/state/audited-projects.json"
}

@test "install-project.sh project registration is idempotent" {
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    count=$(jq --arg p "$TEST_PROJECT" '[.[] | select(.path == $p)] | length' \
        "$TEST_HOME/.claude/state/audited-projects.json")
    [ "$count" = "1" ]
}

@test "install-project.sh does not clobber a user-edited MISTAKES.md" {
    echo "# CUSTOMIZED" > "$TEST_PROJECT/MISTAKES.md"
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    grep -q "CUSTOMIZED" "$TEST_PROJECT/MISTAKES.md"
}
