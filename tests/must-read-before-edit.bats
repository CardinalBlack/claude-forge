#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_STATE_DIR=$(mktemp -d)
    export CLAUDE_READ_LOG="$TEST_STATE_DIR/reads.log"
    : > "$CLAUDE_READ_LOG"
}

teardown() {
    rm -r "$TEST_STATE_DIR" 2>/dev/null || true
}

@test "blocks Edit to a file that wasn't Read" {
    NOT_READ="$TEST_STATE_DIR/foo-not-read.ts"
    : > "$NOT_READ"
    # Ensure the test target file is older than 60s so the mtime escape doesn't trigger.
    touch -t 200001010000 "$NOT_READ" 2>/dev/null || touch -d "2000-01-01" "$NOT_READ"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"'"$NOT_READ"'"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "BLOCKED: read $NOT_READ before editing"
}

@test "allows Edit to a file that WAS Read" {
    WAS_READ="$TEST_STATE_DIR/foo-was-read.ts"
    : > "$WAS_READ"
    echo "$WAS_READ" >> "$CLAUDE_READ_LOG"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"'"$WAS_READ"'"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_success
}

@test "allows Edit to a brand-new file (mtime within 60s)" {
    NEW="$TEST_STATE_DIR/foo-just-created.ts"
    : > "$NEW"  # fresh mtime
    payload='{"tool_name":"Edit","tool_input":{"file_path":"'"$NEW"'"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_success
}

@test "allows Write tool unconditionally (creation case)" {
    NEVER="$TEST_STATE_DIR/never-existed.ts"
    payload='{"tool_name":"Write","tool_input":{"file_path":"'"$NEVER"'"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_success
}

@test "allows when CLAUDE_BYPASS_READ_CHECK=1" {
    BYPASS="$TEST_STATE_DIR/foo-bypass.ts"
    : > "$BYPASS"
    touch -t 200001010000 "$BYPASS" 2>/dev/null || touch -d "2000-01-01" "$BYPASS"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"'"$BYPASS"'"}}'
    CLAUDE_BYPASS_READ_CHECK=1 run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_success
}

@test "no-op when log file does not exist (fail-open)" {
    rm -f "$CLAUDE_READ_LOG"
    WHATEVER="$TEST_STATE_DIR/whatever.ts"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"'"$WHATEVER"'"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_success
}

@test "fail-open on malformed JSON input" {
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "not-json"
    assert_success
}
