#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_CWD=$(mktemp -d)
    export ORIG_CWD="$PWD"
    cd "$TEST_CWD"
}

teardown() {
    cd "$ORIG_CWD"
    rm -r "$TEST_CWD" 2>/dev/null || true
}

# Helper: portable "set mtime to N hours ago" for both GNU and BSD coreutils.
backdate_hours() {
    local file="$1" hours="$2"
    if touch -d "${hours} hours ago" "$file" 2>/dev/null; then
        return 0
    fi
    # BSD form (macOS).
    touch -t "$(date -v-${hours}H +%Y%m%d%H%M)" "$file"
}

write_session_state() {
    cat > SESSION-STATE.md <<'EOF'
# Session State

**Last Updated:** 2026-05-09

## Recently Completed
- did task A
- did task B

## In Progress
- working on task C right now

## Next Up
- task D
- task E

## Active Plan
- Plan file: ./plan.md
- Status: phase 1 of 3

## Key Context
- prefer small commits
EOF
}

@test "no-op if SESSION-STATE.md missing" {
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    [ -z "$output" ]
}

@test "injects In Progress section" {
    write_session_state
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    assert_output --partial "working on task C"
    assert_output --partial "In Progress"
}

@test "injects Next Up section" {
    write_session_state
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    assert_output --partial "task D"
    assert_output --partial "Next Up"
}

@test "injects Active Plan section" {
    write_session_state
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    assert_output --partial "Active Plan"
    assert_output --partial "phase 1 of 3"
}

@test "does NOT include Recently Completed or Key Context" {
    write_session_state
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    refute_output --partial "did task A"
    refute_output --partial "prefer small commits"
}

@test "warns when SESSION-STATE.md > 24h old" {
    write_session_state
    backdate_hours SESSION-STATE.md 25
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    assert_output --partial "STALE"
}

@test "no warn when fresh (< 24h)" {
    write_session_state
    # Don't backdate. mtime is now.
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    refute_output --partial "STALE"
}

@test "output is valid JSON with hookSpecificOutput shape" {
    write_session_state
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< '{"prompt":"hi"}'
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"'
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | type == "string"'
}

@test "drains stdin without choking on payload" {
    write_session_state
    payload='{"session_id":"abc","prompt":"do a thing","cwd":"/tmp/foo","hook_event_name":"UserPromptSubmit"}'
    run bash "$REPO_ROOT/hooks/inject-session-state.sh" <<< "$payload"
    assert_success
    assert_output --partial "working on task C"
}
