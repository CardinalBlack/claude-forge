#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    export TEST_HOME=$(mktemp -d)
    export REAL_HOME="$HOME"
    export HOME="$TEST_HOME"
}

teardown() {
    export HOME="$REAL_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
}

@test "bootstrap.sh creates ~/.claude/skills directory" {
    bash "$REAL_HOME/.claude-bootstrap/bootstrap.sh"
    [ -d "$TEST_HOME/.claude/skills" ]
}

@test "bootstrap.sh creates ~/.claude/agents directory" {
    bash "$REAL_HOME/.claude-bootstrap/bootstrap.sh"
    [ -d "$TEST_HOME/.claude/agents" ]
}
