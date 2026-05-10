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

@test "no output if neither MISTAKES.md nor DEFINITION-OF-DONE.md exists" {
    run bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" <<< '{"prompt":"hello"}'
    assert_success
    [ -z "$output" ]
}

@test "injects MISTAKES.md content if file exists" {
    cat > MISTAKES.md <<'EOF'
- mistake one: did the wrong thing
- mistake two: did another wrong thing
EOF
    run bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" <<< '{"prompt":"hello"}'
    assert_success
    assert_output --partial "mistake one"
    assert_output --partial "mistake two"
    assert_output --partial "Recent mistakes"
}

@test "injects DOD if DOD exists and MISTAKES is missing" {
    cat > DEFINITION-OF-DONE.md <<'EOF'
1. Tests pass
2. Typecheck clean
EOF
    run bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" <<< '{"prompt":"hello"}'
    assert_success
    assert_output --partial "Tests pass"
    assert_output --partial "Definition of done"
}

@test "injects both if both exist" {
    cat > MISTAKES.md <<'EOF'
- some mistake
EOF
    cat > DEFINITION-OF-DONE.md <<'EOF'
1. Tests pass
EOF
    run bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" <<< '{"prompt":"hello"}'
    assert_success
    assert_output --partial "some mistake"
    assert_output --partial "Tests pass"
}

@test "output is valid JSON with hookSpecificOutput shape" {
    cat > MISTAKES.md <<'EOF'
- a mistake
EOF
    run bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" <<< '{"prompt":"hello"}'
    assert_success
    # Re-parse via jq to validate structure.
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"'
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | type == "string"'
}

@test "last-10-only when MISTAKES has 12 entries" {
    {
        for i in $(seq 1 12); do
            echo "- entry-${i}: details for mistake ${i}"
            echo "  continuation line for entry ${i}"
        done
    } > MISTAKES.md
    run bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" <<< '{"prompt":"hello"}'
    assert_success
    # First two entries should NOT appear; last 10 (3..12) should.
    refute_output --partial "entry-1:"
    refute_output --partial "entry-2:"
    assert_output --partial "entry-3:"
    assert_output --partial "entry-12:"
}

@test "drains stdin without choking on payload" {
    cat > MISTAKES.md <<'EOF'
- some mistake
EOF
    # Pass a substantial JSON payload like Claude would.
    payload='{"session_id":"abc","prompt":"do a thing","cwd":"/tmp/foo","hook_event_name":"UserPromptSubmit"}'
    run bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" <<< "$payload"
    assert_success
    assert_output --partial "some mistake"
}
