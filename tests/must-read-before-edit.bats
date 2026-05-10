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
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo-not-read.ts"}}'
    # Ensure the test target file is older than 60s so the mtime escape doesn't trigger.
    : > /tmp/foo-not-read.ts
    touch -t 200001010000 /tmp/foo-not-read.ts 2>/dev/null || touch -d "2000-01-01" /tmp/foo-not-read.ts
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    rm -f /tmp/foo-not-read.ts
    assert_failure 2
    assert_output --partial "BLOCKED: read /tmp/foo-not-read.ts before editing"
}

@test "allows Edit to a file that WAS Read" {
    : > /tmp/foo-was-read.ts
    echo "/tmp/foo-was-read.ts" >> "$CLAUDE_READ_LOG"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo-was-read.ts"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    rm -f /tmp/foo-was-read.ts
    assert_success
}

@test "allows Edit to a brand-new file (mtime within 60s)" {
    NEW=/tmp/foo-just-created.ts
    : > "$NEW"  # fresh mtime
    payload='{"tool_name":"Edit","tool_input":{"file_path":"'"$NEW"'"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    rm -f "$NEW"
    assert_success
}

@test "allows Write tool unconditionally (creation case)" {
    payload='{"tool_name":"Write","tool_input":{"file_path":"/tmp/never-existed.ts"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_success
}

@test "allows when CLAUDE_BYPASS_READ_CHECK=1" {
    : > /tmp/foo-bypass.ts
    touch -t 200001010000 /tmp/foo-bypass.ts 2>/dev/null || touch -d "2000-01-01" /tmp/foo-bypass.ts
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo-bypass.ts"}}'
    CLAUDE_BYPASS_READ_CHECK=1 run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    rm -f /tmp/foo-bypass.ts
    assert_success
}

@test "no-op when log file does not exist (fail-open)" {
    rm -f "$CLAUDE_READ_LOG"
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/whatever.ts"}}'
    run bash "$REPO_ROOT/hooks/must-read-before-edit.sh" <<< "$payload"
    assert_success
}
