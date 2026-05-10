#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_REPO=$(mktemp -d)
    cd "$TEST_REPO"
    # Initialize a git repo on `main` so default branch is deterministic
    # across systems (older git defaults to `master`).
    git init -q -b main 2>/dev/null || { git init -q && git symbolic-ref HEAD refs/heads/main; }
    git config user.email "t@t.test"
    git config user.name "Tester"
    # Need at least one commit so `git branch --show-current` returns a name.
    : > seed.txt
    git add seed.txt
    git -c commit.gpgsign=false commit -q -m "seed"
}

teardown() {
    cd /
    rm -r "$TEST_REPO" 2>/dev/null || true
}

@test "blocks git commit on main" {
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"some change\""}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "BLOCKED: cannot commit directly to main"
}

@test "blocks git commit on master" {
    git checkout -q -b master
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"some change\""}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_failure 2
    assert_output --partial "BLOCKED: cannot commit directly to main"
}

@test "allows git commit on a feature branch" {
    git checkout -q -b feat/x
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"some change\""}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "allows main commit with ALLOW-MAIN-COMMIT in message" {
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"hotfix ALLOW-MAIN-COMMIT: prod is down\""}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "allows main commit when CLAUDE_ALLOW_MAIN=1" {
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"some change\""}}'
    CLAUDE_ALLOW_MAIN=1 run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "ignores non-git Bash commands" {
    payload='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "ignores non-Bash tools" {
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.ts"}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "ignores git commit-tree (does not match commit-prefix false positive)" {
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit-tree HEAD^{tree} -m foo"}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "ignores git commit-graph write" {
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit-graph write"}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "fail-open on malformed JSON input" {
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "not-json"
    assert_success
}

@test "ignores other git subcommands on main (status, log)" {
    payload='{"tool_name":"Bash","tool_input":{"command":"git status"}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    assert_success
}

@test "exits cleanly when not in a git repo" {
    cd /
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"}}'
    run bash "$REPO_ROOT/hooks/block-direct-main-commit.sh" <<< "$payload"
    # Empty branch != main/master → allow.
    assert_success
}
