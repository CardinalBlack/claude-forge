#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

# Mocks `claude` by prepending a temp bin dir to PATH. The mock writes a
# fixed string to stdout — that's what the hook will capture as $SUMMARY
# and forward to stderr. Tests assert presence of the banner + mock text.

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_REPO=$(mktemp -d)
    export TEST_BIN=$(mktemp -d)
    cd "$TEST_REPO"
    git init -q -b main 2>/dev/null || { git init -q && git symbolic-ref HEAD refs/heads/main; }
    git config user.email "t@t.test"
    git config user.name "Tester"
    # Seed commit so subsequent staged-diff comparisons have a HEAD.
    : > seed.txt
    git add seed.txt
    git -c commit.gpgsign=false commit -q -m "seed"

    # Default mock: echoes a recognizable summary. Tests that want
    # "no claude on PATH" or "claude returns non-zero" override this.
    cat > "$TEST_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
# Mock claude CLI. Ignores all args; just emits a fixed summary so the
# test can assert it was invoked.
echo "Mock summary: 2 files changed, no risky patterns."
MOCK
    chmod +x "$TEST_BIN/claude"

    # Save original PATH so individual tests can opt out cleanly.
    export ORIG_PATH="$PATH"
    export PATH="$TEST_BIN:$PATH"
}

teardown() {
    cd /
    # Restore PATH so the mock can't leak into subsequent suites.
    export PATH="${ORIG_PATH:-$PATH}"
    rm -r "$TEST_REPO" 2>/dev/null || true
    rm -r "$TEST_BIN" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Gate: tool / command / branch / staged-diff filters
# -----------------------------------------------------------------------------

@test "no-op on non-Bash tool (Edit)" {
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.ts"}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    refute_output --partial "Pre-commit summary"
}

@test "no-op on non-git-commit Bash command (ls)" {
    payload='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    refute_output --partial "Pre-commit summary"
}

@test "no-op on git commit-tree (does not match commit-prefix false positive)" {
    echo "x" > a.txt
    git add a.txt
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit-tree HEAD^{tree} -m foo"}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    refute_output --partial "Pre-commit summary"
}

@test "no-op on feature branch (not main/master)" {
    git checkout -q -b feat/x
    echo "change" > a.txt
    git add a.txt
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add a\""}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    refute_output --partial "Pre-commit summary"
}

@test "no-op when no staged changes on main" {
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"empty\""}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    refute_output --partial "Pre-commit summary"
}

@test "no-op when claude not on PATH" {
    echo "change" > a.txt
    git add a.txt
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
    # Strip the mock dir from PATH for just this run.
    PATH="/usr/bin:/bin" run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    refute_output --partial "Pre-commit summary"
}

@test "no-op when SKIP-SUMMARY: in commit message" {
    echo "change" > a.txt
    git add a.txt
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"hotfix SKIP-SUMMARY: emergency\""}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    refute_output --partial "Pre-commit summary"
}

# -----------------------------------------------------------------------------
# Happy path: gate passes → claude invoked → summary on stderr
# -----------------------------------------------------------------------------

@test "fires on main with staged diff and claude on PATH (summary -> stderr)" {
    echo "new line" > a.txt
    git add a.txt
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add a\""}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    # `run` merges stderr+stdout into $output by default in bats. We
    # printed to stderr; both banner and mock summary should appear.
    assert_output --partial "Pre-commit summary (Haiku)"
    assert_output --partial "Mock summary: 2 files changed"
}

@test "fires on master branch (not just main)" {
    # Recreate the repo on master to be deterministic.
    cd /
    rm -rf "$TEST_REPO"
    export TEST_REPO=$(mktemp -d)
    cd "$TEST_REPO"
    git init -q -b master 2>/dev/null || { git init -q && git symbolic-ref HEAD refs/heads/master; }
    git config user.email "t@t.test"
    git config user.name "Tester"
    : > seed.txt
    git add seed.txt
    git -c commit.gpgsign=false commit -q -m "seed"

    echo "change" > a.txt
    git add a.txt
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add a\""}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    assert_output --partial "Pre-commit summary (Haiku)"
}

# -----------------------------------------------------------------------------
# Fail-open: hook NEVER blocks the commit
# -----------------------------------------------------------------------------

@test "hook exits 0 even when claude returns non-zero" {
    # Replace mock with a failing one.
    cat > "$TEST_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
echo "claude exploded" >&2
exit 7
MOCK
    chmod +x "$TEST_BIN/claude"

    echo "change" > a.txt
    git add a.txt
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "$payload"
    assert_success
    # No banner printed (the hook bailed silently on non-zero).
    refute_output --partial "Pre-commit summary"
    # And claude's stderr noise must not have leaked through.
    refute_output --partial "claude exploded"
}

@test "fail-open on malformed JSON payload" {
    run bash "$REPO_ROOT/hooks/summarize-commit-diff.sh" <<< "not-json"
    assert_success
    refute_output --partial "Pre-commit summary"
}
