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

@test "bootstrap.sh installs hooks into settings.json" {
    bash "$REPO_ROOT/bootstrap.sh"
    [ -f "$TEST_HOME/.claude/settings.json" ]
    grep -q "must-read-before-edit.sh" "$TEST_HOME/.claude/settings.json"
    grep -q "kill-switch.sh" "$TEST_HOME/.claude/settings.json"
    grep -q "require-verification-before-done.sh" "$TEST_HOME/.claude/settings.json"
}

@test "bootstrap.sh hook installation is idempotent" {
    bash "$REPO_ROOT/bootstrap.sh"
    bash "$REPO_ROOT/bootstrap.sh"
    count=$(jq '[.. | objects | select(.command? != null) | select(.command | contains("must-read-before-edit.sh"))] | length' \
        "$TEST_HOME/.claude/settings.json")
    [ "$count" = "1" ]
}
