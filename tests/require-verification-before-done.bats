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

# Helper: write a fake transcript file with the given content and return its path.
# The hook only does substring grep on the tail of the file, so any text works.
write_transcript() {
    local content="$1"
    local file="$TEST_CWD/transcript.jsonl"
    printf '%s' "$content" > "$file"
    echo "$file"
}

@test "warns when 'done' claimed but no test run found" {
    transcript=$(write_transcript 'I edited the file. All done!')
    payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
    assert_output --partial "hookSpecificOutput"
    assert_output --partial "additionalContext"
    assert_output --partial "no verification"
}

@test "no warning when 'done' claimed AND tests ran recently" {
    transcript=$(write_transcript '
Ran the suite:
Test Files  22 passed (22)
     Tests  314 passed (314)
All done!
')
    payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
    [ -z "$output" ]
}

@test "no warning when no done-claim is present" {
    transcript=$(write_transcript 'I am still working on the implementation. Reading more files.')
    payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
    [ -z "$output" ]
}

@test "no-op when transcript_path missing from payload" {
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< '{}'
    assert_success
    [ -z "$output" ]
}

@test "no-op when transcript_path points to nonexistent file" {
    payload='{"transcript_path":"/tmp/does-not-exist-'$$'.jsonl"}'
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
    [ -z "$output" ]
}

@test "fail-open on malformed JSON payload" {
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< 'not-json{{{'
    assert_success
    [ -z "$output" ]
}

@test "warns on each done-claim variant" {
    # Regex tightened in v1.1: dropped 'complete', 'verified', 'fixed', plain
    # 'ready to' and bare 'passes' (all matched conversational uses in
    # UI/content turns where no typecheck applies). Kept: high-signal markers
    # only.
    for claim in "all done!" "tests pass" "tests passed" "it works" "shipped" "ready to merge" "ready to deploy" "ready to ship" "✅ green across the board"; do
        transcript=$(write_transcript "Some neutral build text. $claim")
        payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
        run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
        assert_success
        # "tests pass" / "tests passed" are BOTH done-claim AND verification
        # marker, so they short-circuit to silent. Skip warning assertion.
        case "$claim" in
            "tests pass"|"tests passed")
                [ -z "$output" ] || (echo "expected empty for '$claim'; got: $output" && false)
                ;;
            *)
                echo "$output" | grep -q "hookSpecificOutput" || (echo "no warning for variant: $claim; output: $output" && false)
                ;;
        esac
    done
}

@test "does NOT warn on dropped conversational done-words (regression guard for v1.1 regex tightening)" {
    # These all fired the old regex spuriously. The tightened regex must
    # NOT fire on them.
    for claim in "I verified the change is consistent" "fixed a typo earlier" "implementation is complete enough to discuss" "ready to discuss next steps" "this passes through middleware" "everything looks complete from here"; do
        transcript=$(write_transcript "Some neutral build text. $claim")
        payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
        run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
        assert_success
        [ -z "$output" ] || (echo "expected silent for dropped variant: $claim; got: $output" && false)
    done
}

@test "suppresses warning on each verification marker variant" {
    for marker in "tsc --noEmit completed cleanly" "ran typecheck" "vitest reports green" "jest finished" "pytest collected 5 items" "✓ tests"; do
        transcript=$(write_transcript "$marker. All done!")
        payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
        run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
        assert_success
        [ -z "$output" ] || (echo "expected silent for marker: $marker; got: $output" && false)
    done
}

@test "output is valid JSON with hookSpecificOutput shape" {
    transcript=$(write_transcript 'All done!')
    payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
    echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "Stop"'
    echo "$output" | jq -e '.hookSpecificOutput.additionalContext | type == "string"'
}

@test "output is single-line compact JSON" {
    transcript=$(write_transcript 'All done!')
    payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
    # Compact JSON: exactly one line of stdout.
    [ "$(printf '%s' "$output" | wc -l | tr -d ' ')" = "0" ]
}

@test "exits 0 in warning path (Stop hook does not block)" {
    transcript=$(write_transcript 'All done!')
    payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
}

@test "case-insensitive done-claim detection" {
    transcript=$(write_transcript 'ALL DONE!')
    payload=$(jq -nc --arg t "$transcript" '{transcript_path: $t}')
    run bash "$REPO_ROOT/hooks/require-verification-before-done.sh" <<< "$payload"
    assert_success
    assert_output --partial "hookSpecificOutput"
}
