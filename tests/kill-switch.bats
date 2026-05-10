#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_HOME=$(mktemp -d)
    export ORIG_HOME="$HOME"
    export HOME="$TEST_HOME"
    mkdir -p "$HOME/.claude"
}

teardown() {
    export HOME="$ORIG_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
}

@test "blocks any tool when PAUSE_AND_REVIEW exists" {
    : > "$HOME/.claude/PAUSE_AND_REVIEW"
    payload='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run env HOME="$HOME" bash "$REPO_ROOT/hooks/kill-switch.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "BLOCKED"
    assert_output --partial "PAUSED"
}

@test "allows when PAUSE_AND_REVIEW does not exist" {
    payload='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run env HOME="$HOME" bash "$REPO_ROOT/hooks/kill-switch.sh" <<< "$payload"
    assert_success
}

@test "surfaces reason content if file has it" {
    echo "stop touching prod" > "$HOME/.claude/PAUSE_AND_REVIEW"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.ts"}}'
    run env HOME="$HOME" bash "$REPO_ROOT/hooks/kill-switch.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "stop touching prod"
}

@test "empty reason file is safe" {
    : > "$HOME/.claude/PAUSE_AND_REVIEW"
    payload='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    run env HOME="$HOME" bash "$REPO_ROOT/hooks/kill-switch.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "BLOCKED"
    assert_output --partial "Reason:"
}

@test "blocks Bash tool when paused" {
    : > "$HOME/.claude/PAUSE_AND_REVIEW"
    payload='{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
    run env HOME="$HOME" bash "$REPO_ROOT/hooks/kill-switch.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "BLOCKED"
}

@test "blocks Edit tool when paused" {
    : > "$HOME/.claude/PAUSE_AND_REVIEW"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.ts"}}'
    run env HOME="$HOME" bash "$REPO_ROOT/hooks/kill-switch.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "BLOCKED"
}
