#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

@test "Makefile exists at repo root" {
    [ -f "$REPO_ROOT/Makefile" ]
}

@test "Makefile declares the four standard targets" {
    grep -qE "^install:" "$REPO_ROOT/Makefile"
    grep -qE "^test:" "$REPO_ROOT/Makefile"
    grep -qE "^update:" "$REPO_ROOT/Makefile"
    grep -qE "^ci:" "$REPO_ROOT/Makefile"
}

@test "make test target invokes the bats suite via the expected path" {
    # Use `make -n` (dry-run) to verify the target prints the bats invocation
    # WITHOUT actually re-executing the suite. Running `make test` here would
    # be infinite recursion: this .bats file is inside tests/, so `make test`
    # would re-enter the suite and re-fire this test, which would call
    # `make test` again, ad infinitum until OOM.
    cd "$REPO_ROOT"
    output=$(make -n test 2>&1)
    [[ "$output" == *"bats"* ]]
    [[ "$output" == *"tests/"* ]]
}

@test "make install target invokes bootstrap.sh" {
    cd "$REPO_ROOT"
    output=$(make -n install 2>&1)
    [[ "$output" == *"bootstrap.sh"* ]]
}

@test "make ci target depends on test (chains correctly)" {
    cd "$REPO_ROOT"
    output=$(make -n ci 2>&1)
    [[ "$output" == *"bats"* ]]
}

@test "Makefile declares its targets as .PHONY" {
    # Without .PHONY, `make install` becomes a no-op once an `install`
    # file/dir exists at repo root — silently breaks the user's `make install`.
    grep -qE "^\.PHONY:" "$REPO_ROOT/Makefile"
}
