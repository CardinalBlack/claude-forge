#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_REPO=$(mktemp -d)
    export MOCK_BIN="$TEST_REPO/bin"
    mkdir -p "$MOCK_BIN"
    cd "$TEST_REPO"
    git init -q -b main 2>/dev/null || { git init -q && git symbolic-ref HEAD refs/heads/main; }
    git config user.email "t@t.test"
    git config user.name "Tester"
    : > seed.txt
    git add seed.txt
    git -c commit.gpgsign=false commit -q -m "seed"

    # Mock `claude` CLI. Per-test customizable via MOCK_CLAUDE_RESPONSE and
    # MOCK_CLAUDE_EXIT. Drops a marker file every invocation so tests can
    # assert claude was (or wasn't) called.
    cat > "$MOCK_BIN/claude" <<'MOCK'
#!/usr/bin/env bash
touch "$MOCK_CLAUDE_MARKER"
echo "${MOCK_CLAUDE_RESPONSE:-No risks detected.}"
exit "${MOCK_CLAUDE_EXIT:-0}"
MOCK
    chmod +x "$MOCK_BIN/claude"
    export MOCK_CLAUDE_MARKER="$TEST_REPO/.claude-invoked"
    # Prepend mock bin so the hook picks up our `claude`.
    export PATH="$MOCK_BIN:$PATH"
}

teardown() {
    cd /
    rm -r "$TEST_REPO" 2>/dev/null || true
}

# Helper: write a RISKY-PATHS.md with the standard patterns from the spec.
write_standard_risky_paths() {
    cat > RISKY-PATHS.md <<'EOF'
- `**/*auth*/**`
- `**/middleware.{ts,js}`
- `**/migrations/**/*.sql`
- `apps/web/src/server/lib/agent/sarah/**`
EOF
}

# -----------------------------------------------------------------------------
# No-op gates
# -----------------------------------------------------------------------------

@test "no-op when RISKY-PATHS.md does not exist" {
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add apps/web/app/api/auth/login/route.ts
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add auth\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

@test "no-op when RISKY-PATHS.md exists but no staged file matches" {
    write_standard_risky_paths
    echo "harmless" > README.md
    git add README.md RISKY-PATHS.md
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"docs\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

@test "no-op when command is not git commit" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add -A
    payload='{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

@test "no-op for git commit-tree (commit-prefix false positive)" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add -A
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit-tree HEAD^{tree} -m foo"}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

@test "no-op for non-Bash tools" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add -A
    payload='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/x.ts"}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

@test "no-op when no files are staged" {
    write_standard_risky_paths
    git add RISKY-PATHS.md
    git -c commit.gpgsign=false commit -q -m "add risky paths" RISKY-PATHS.md
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"empty\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

# -----------------------------------------------------------------------------
# Match → review → verdict
# -----------------------------------------------------------------------------

@test "fires when staged file matches a pattern (auth/**)" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "export const handler = () => 1;" > apps/web/app/api/auth/login/route.ts
    git add apps/web/app/api/auth/login/route.ts RISKY-PATHS.md
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add auth route\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ -f "$MOCK_CLAUDE_MARKER" ]
    assert_output --partial "Risky-path review"
    assert_output --partial "apps/web/app/api/auth/login/route.ts"
}

@test "blocks (exit 2) when mock review returns concerns" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "export const handler = () => 1;" > apps/web/app/api/auth/login/route.ts
    git add apps/web/app/api/auth/login/route.ts RISKY-PATHS.md
    export MOCK_CLAUDE_RESPONSE="Concern: missing input validation on the login handler. Could leak credentials."
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add auth route\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_failure 2
    [ -f "$MOCK_CLAUDE_MARKER" ]
    assert_output --partial "BLOCKED: risky-path review"
    assert_output --partial "SKIP-RISKY-REVIEW:"
    assert_output --partial "Concern: missing input validation"
}

@test "allows (exit 0) when mock review says 'No risks detected'" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "export const handler = () => 1;" > apps/web/app/api/auth/login/route.ts
    git add apps/web/app/api/auth/login/route.ts RISKY-PATHS.md
    # Default mock response is "No risks detected."
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add auth route\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ -f "$MOCK_CLAUDE_MARKER" ]
    assert_output --partial "No risks detected"
}

@test "verdict match is case-insensitive ('NO RISKS DETECTED')" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add -A
    export MOCK_CLAUDE_RESPONSE="NO RISKS DETECTED in this diff."
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
}

# -----------------------------------------------------------------------------
# Override
# -----------------------------------------------------------------------------

@test "honors SKIP-RISKY-REVIEW: override without invoking claude" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add -A
    # Even though the mock would return concerns, the override should
    # short-circuit before claude is called.
    export MOCK_CLAUDE_RESPONSE="Concern: this is bad"
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"intentional SKIP-RISKY-REVIEW: documenting auth example\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    # claude must NOT have been invoked.
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

# -----------------------------------------------------------------------------
# Glob coverage
# -----------------------------------------------------------------------------

@test "glob matches ** recursive pattern (apps/web/src/server/lib/agent/sarah/**)" {
    write_standard_risky_paths
    mkdir -p apps/web/src/server/lib/agent/sarah/turn
    echo "x" > apps/web/src/server/lib/agent/sarah/turn/route.ts
    git add -A
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"sarah\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ -f "$MOCK_CLAUDE_MARKER" ]
    assert_output --partial "apps/web/src/server/lib/agent/sarah/turn/route.ts"
}

@test "glob honors deep paths with brace expansion (**/middleware.{ts,js})" {
    write_standard_risky_paths
    mkdir -p apps/web
    echo "x" > apps/web/middleware.ts
    git add -A
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"mw\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ -f "$MOCK_CLAUDE_MARKER" ]
    assert_output --partial "apps/web/middleware.ts"
}

@test "glob matches **/migrations/**/*.sql on nested SQL" {
    write_standard_risky_paths
    mkdir -p db/migrations/2025
    echo "SELECT 1;" > db/migrations/2025/001.sql
    git add -A
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"migration\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ -f "$MOCK_CLAUDE_MARKER" ]
    assert_output --partial "db/migrations/2025/001.sql"
}

# -----------------------------------------------------------------------------
# Fail-open coverage
# -----------------------------------------------------------------------------

@test "fail-open when claude is not on PATH" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add -A
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
    # Stripped PATH — no claude available.
    PATH="/usr/bin:/bin" run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    assert_success
    [ ! -f "$MOCK_CLAUDE_MARKER" ]
}

@test "fail-open on malformed JSON payload" {
    write_standard_risky_paths
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "not-json"
    assert_success
}

@test "fail-open when claude exits non-zero (tooling failure)" {
    write_standard_risky_paths
    mkdir -p apps/web/app/api/auth/login
    echo "x" > apps/web/app/api/auth/login/route.ts
    git add -A
    export MOCK_CLAUDE_EXIT=1
    export MOCK_CLAUDE_RESPONSE="auth error"
    payload='{"tool_name":"Bash","tool_input":{"command":"git commit -m \"x\""}}'
    run bash "$REPO_ROOT/hooks/risky-path-review.sh" <<< "$payload"
    # Tooling failed — don't block.
    assert_success
}
