#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "repo skeleton exists" {
    [ -d "$REPO_ROOT/hooks" ]
    [ -d "$REPO_ROOT/skills" ]
    [ -d "$REPO_ROOT/agents" ]
    [ -d "$REPO_ROOT/templates" ]
    [ -d "$REPO_ROOT/crons" ]
}
