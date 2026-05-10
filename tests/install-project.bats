#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    export TEST_PROJECT=$(mktemp -d)
    cd "$TEST_PROJECT"
    git init -q -b main
}

teardown() {
    rm -r "$TEST_PROJECT" 2>/dev/null || true
}

@test "install-project.sh creates MISTAKES.md" {
    bash "$HOME/.claude-bootstrap/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/MISTAKES.md" ]
}

@test "install-project.sh creates DEFINITION-OF-DONE.md" {
    bash "$HOME/.claude-bootstrap/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/DEFINITION-OF-DONE.md" ]
}

@test "install-project.sh creates RISKY-PATHS.md" {
    bash "$HOME/.claude-bootstrap/install-project.sh" "$TEST_PROJECT"
    [ -f "$TEST_PROJECT/RISKY-PATHS.md" ]
}
