#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_STATE_DIR=$(mktemp -d)
    export CLAUDE_READ_LOG="$TEST_STATE_DIR/reads.log"
}

teardown() {
    rm -r "$TEST_STATE_DIR" 2>/dev/null || true
}

@test "appends file path on successful Read" {
    payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/x.ts"}}'
    bash "$REPO_ROOT/hooks/log-read-paths.sh" <<< "$payload"
    grep -qxF "/tmp/x.ts" "$CLAUDE_READ_LOG"
}

@test "does not append on non-Read tools" {
    payload='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
    bash "$REPO_ROOT/hooks/log-read-paths.sh" <<< "$payload"
    [ ! -s "$CLAUDE_READ_LOG" ] || [ ! -f "$CLAUDE_READ_LOG" ]
}

@test "creates log dir if missing" {
    NEW_DIR="$TEST_STATE_DIR/sub/nested"
    export CLAUDE_READ_LOG="$NEW_DIR/reads.log"
    payload='{"tool_name":"Read","tool_input":{"file_path":"/tmp/y.ts"}}'
    bash "$REPO_ROOT/hooks/log-read-paths.sh" <<< "$payload"
    [ -f "$CLAUDE_READ_LOG" ]
    grep -qxF "/tmp/y.ts" "$CLAUDE_READ_LOG"
}

@test "appends multiple paths in order" {
    bash "$REPO_ROOT/hooks/log-read-paths.sh" <<< '{"tool_name":"Read","tool_input":{"file_path":"/a"}}'
    bash "$REPO_ROOT/hooks/log-read-paths.sh" <<< '{"tool_name":"Read","tool_input":{"file_path":"/b"}}'
    bash "$REPO_ROOT/hooks/log-read-paths.sh" <<< '{"tool_name":"Read","tool_input":{"file_path":"/c"}}'
    [ "$(wc -l < "$CLAUDE_READ_LOG")" -eq 3 ]
    [ "$(head -1 "$CLAUDE_READ_LOG")" = "/a" ]
    [ "$(tail -1 "$CLAUDE_READ_LOG")" = "/c" ]
}
