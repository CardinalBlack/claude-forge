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
