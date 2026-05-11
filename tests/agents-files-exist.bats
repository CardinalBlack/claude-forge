#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

@test "code-reviewer agent file exists" {
    [ -f "$REPO_ROOT/agents/code-reviewer.md" ]
    grep -q "^name: code-reviewer" "$REPO_ROOT/agents/code-reviewer.md"
}

@test "devils-advocate agent file exists" {
    [ -f "$REPO_ROOT/agents/devils-advocate.md" ]
    grep -q "^name: devils-advocate" "$REPO_ROOT/agents/devils-advocate.md"
}

@test "task-debriefer agent file exists" {
    [ -f "$REPO_ROOT/agents/task-debriefer.md" ]
    grep -q "^name: task-debriefer" "$REPO_ROOT/agents/task-debriefer.md"
}
