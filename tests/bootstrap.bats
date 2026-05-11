#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export TEST_HOME=$(mktemp -d)
    export REAL_HOME="$HOME"
    export HOME="$TEST_HOME"
}

teardown() {
    export HOME="$REAL_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
}

@test "bootstrap.sh creates ~/.claude/skills directory" {
    bash "$REPO_ROOT/bootstrap.sh"
    [ -d "$TEST_HOME/.claude/skills" ]
}

@test "bootstrap.sh creates ~/.claude/agents directory" {
    bash "$REPO_ROOT/bootstrap.sh"
    [ -d "$TEST_HOME/.claude/agents" ]
}

@test "bootstrap.sh installs hooks into settings.json" {
    bash "$REPO_ROOT/bootstrap.sh"
    [ -f "$TEST_HOME/.claude/settings.json" ]
    grep -q "must-read-before-edit.sh" "$TEST_HOME/.claude/settings.json"
    grep -q "kill-switch.sh" "$TEST_HOME/.claude/settings.json"
    grep -q "require-verification-before-done.sh" "$TEST_HOME/.claude/settings.json"
}

@test "bootstrap.sh hook installation is idempotent" {
    bash "$REPO_ROOT/bootstrap.sh"
    bash "$REPO_ROOT/bootstrap.sh"
    count=$(jq '[.. | objects | select(.command? != null) | select(.command | contains("must-read-before-edit.sh"))] | length' \
        "$TEST_HOME/.claude/settings.json")
    [ "$count" = "1" ]
}

@test "bootstrap.sh symlinks every shipped skill into ~/.claude/skills/" {
    bash "$REPO_ROOT/bootstrap.sh"
    for SKILL_DIR in "$REPO_ROOT/skills"/*/; do
        NAME=$(basename "$SKILL_DIR")
        [ -L "$TEST_HOME/.claude/skills/$NAME" ]
        # Resolve symlink target and confirm it points at the shipped skill dir
        # (so `git pull` in the bootstrap repo updates user-facing skills).
        TARGET=$(readlink "$TEST_HOME/.claude/skills/$NAME")
        [[ "$TARGET" == *"/skills/$NAME"* ]] || [[ "$TARGET" == *"/skills/$NAME/" ]]
    done
}

@test "bootstrap.sh symlinks every shipped agent into ~/.claude/agents/" {
    bash "$REPO_ROOT/bootstrap.sh"
    for AGENT_FILE in "$REPO_ROOT/agents"/*.md; do
        NAME=$(basename "$AGENT_FILE")
        [ -L "$TEST_HOME/.claude/agents/$NAME" ]
    done
}

@test "bootstrap.sh symlink installation is idempotent (re-run preserves links)" {
    bash "$REPO_ROOT/bootstrap.sh"
    bash "$REPO_ROOT/bootstrap.sh"
    # Same set of skills/agents present; no duplicate entries, no broken links.
    SKILL_COUNT=$(ls "$TEST_HOME/.claude/skills" | wc -l | tr -d ' ')
    EXPECTED=$(ls -d "$REPO_ROOT/skills"/*/ | wc -l | tr -d ' ')
    [ "$SKILL_COUNT" = "$EXPECTED" ]
}

@test "bootstrap.sh refuses to clobber a real directory at \$CLAUDE_HOME/skills/<name>" {
    # User has a non-symlink directory at the install target — bootstrap must
    # NOT replace it (could be user's hand-curated skill), only warn + skip.
    mkdir -p "$TEST_HOME/.claude/skills/pre-flight-checklist"
    echo "user content" > "$TEST_HOME/.claude/skills/pre-flight-checklist/USER.md"
    bash "$REPO_ROOT/bootstrap.sh"
    [ ! -L "$TEST_HOME/.claude/skills/pre-flight-checklist" ]
    [ -f "$TEST_HOME/.claude/skills/pre-flight-checklist/USER.md" ]
}

@test "bootstrap.sh skips install-crons.sh when it doesn't exist (Phase 6 not yet shipped)" {
    # Phase 5 ships before Phase 6. bootstrap.sh must not abort if
    # scripts/install-crons.sh is absent — should silently no-op that step.
    run bash "$REPO_ROOT/bootstrap.sh"
    [ "$status" -eq 0 ]
}
