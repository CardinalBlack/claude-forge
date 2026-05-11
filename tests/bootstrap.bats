#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export TEST_HOME=$(mktemp -d)
    export REAL_HOME="$HOME"
    export HOME="$TEST_HOME"
    # Test seam: bootstrap.sh invokes scripts/install-crons.sh, which mutates
    # the user's real crontab unless CLAUDE_CRONTAB_FILE is set. Redirect to
    # a temp file so bats runs never touch the real crontab. Without this,
    # `bats tests/` would silently install daily-review/weekly-audit cron
    # entries into the developer's actual crontab on every test run.
    export CLAUDE_CRONTAB_FILE=$(mktemp)
}

teardown() {
    export HOME="$REAL_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
    rm -f "$CLAUDE_CRONTAB_FILE" 2>/dev/null || true
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

@test "bootstrap.sh runs install-crons.sh when present (Phase 6 shipped)" {
    # Phase 5 added a conditional invocation of scripts/install-crons.sh.
    # With Phase 6 shipped, the script exists and bootstrap.sh should
    # invoke it. The CLAUDE_CRONTAB_FILE seam (set in setup) redirects
    # the crontab mutation to a temp file so this assertion is hermetic.
    run bash "$REPO_ROOT/bootstrap.sh"
    [ "$status" -eq 0 ]
    # Daily and weekly entries should land in the test-seam file.
    grep -q "daily-review.sh" "$CLAUDE_CRONTAB_FILE"
    grep -q "weekly-audit.sh" "$CLAUDE_CRONTAB_FILE"
}

@test "bootstrap.sh tolerates install-crons.sh absence (forward compatibility)" {
    # Defensive: if a future refactor removes or renames install-crons.sh
    # (or it's deleted in a partial checkout), bootstrap.sh must still
    # succeed for the rest of the install. Simulate by temporarily
    # renaming the script.
    mv "$REPO_ROOT/scripts/install-crons.sh" "$REPO_ROOT/scripts/install-crons.sh.bak"
    run bash "$REPO_ROOT/bootstrap.sh"
    rc=$status
    mv "$REPO_ROOT/scripts/install-crons.sh.bak" "$REPO_ROOT/scripts/install-crons.sh"
    [ "$rc" -eq 0 ]
}
