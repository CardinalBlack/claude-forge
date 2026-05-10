#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export TEST_HOME=$(mktemp -d)
    export REAL_HOME="$HOME"
    export HOME="$TEST_HOME"
}

teardown() {
    export HOME="$REAL_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
}

@test "bootstrap.sh creates ~/.claude/skills directory" {
    bash "$REPO_ROOT/bootstrap.sh"
    [ -d "$TEST_HOME/.claude/skills" ]
}

@test "bootstrap.sh creates ~/.claude/agents directory" {
    bash "$REPO_ROOT/bootstrap.sh"
    [ -d "$TEST_HOME/.claude/agents" ]
}
