#!/usr/bin/env bats
#
# Final integration test (Phase 9.3): exercises the full install pipeline
# end-to-end against a hermetic temp environment, then asserts the entire
# resulting state — every skill symlinked, every agent symlinked, every
# hook merged into settings.json, every template dropped into the test
# project, audited-projects.json populated, AND a hook actually fires
# correctly against the resulting install.
#
# Unlike the per-script tests (bootstrap.bats, install-project.bats), this
# test exercises the TWO installers TOGETHER and verifies the composed
# end-state. A regression in either installer's output, or a regression in
# how the global + per-project layers interact, would surface here.

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
    export TEST_HOME=$(mktemp -d)
    export REAL_HOME="$HOME"
    export HOME="$TEST_HOME"
    export TEST_PROJECT=$(mktemp -d)
    export CLAUDE_CRONTAB_FILE=$(mktemp)
    cd "$TEST_PROJECT"
    git init -q -b main
}

teardown() {
    export HOME="$REAL_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
    rm -r "$TEST_PROJECT" 2>/dev/null || true
    rm -f "$CLAUDE_CRONTAB_FILE" 2>/dev/null || true
}

@test "integration: full pipeline produces a complete working install" {
    # ── Stage 1: run bootstrap.sh and assert the global layer is wired
    run bash "$REPO_ROOT/bootstrap.sh"
    [ "$status" -eq 0 ]

    # Every shipped skill must be symlinked into TEST_HOME/.claude/skills/
    for SKILL_DIR in "$REPO_ROOT/skills"/*/; do
        NAME=$(basename "$SKILL_DIR")
        [ -L "$TEST_HOME/.claude/skills/$NAME" ] || {
            echo "skill not symlinked: $NAME" >&2
            return 1
        }
        # And the symlink target must exist (no broken links).
        target=$(readlink "$TEST_HOME/.claude/skills/$NAME")
        [ -e "$target" ] || {
            echo "broken symlink: $NAME → $target" >&2
            return 1
        }
    done

    # Every shipped agent must be symlinked into TEST_HOME/.claude/agents/
    for AGENT_FILE in "$REPO_ROOT/agents"/*.md; do
        NAME=$(basename "$AGENT_FILE")
        [ -L "$TEST_HOME/.claude/agents/$NAME" ] || {
            echo "agent not symlinked: $NAME" >&2
            return 1
        }
    done

    # All seven hooks present in settings.json by absolute-path command.
    for HOOK in must-read-before-edit log-read-paths kill-switch \
                inject-mistakes-and-dod inject-session-state \
                block-direct-main-commit require-verification-before-done; do
        grep -q "${HOOK}.sh" "$TEST_HOME/.claude/settings.json" || {
            echo "hook not in settings.json: $HOOK" >&2
            return 1
        }
    done

    # Both cron entries present in the test-seam file.
    grep -q "daily-review.sh" "$CLAUDE_CRONTAB_FILE"
    grep -q "weekly-audit.sh" "$CLAUDE_CRONTAB_FILE"

    # State directories exist for hook bookkeeping.
    [ -d "$TEST_HOME/.claude/state" ]
    [ -d "$TEST_HOME/.claude/reports" ]
    [ -d "$TEST_HOME/.claude/forensics" ]

    # ── Stage 2: run install-project.sh against the test project
    run bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    # All eight per-project templates landed.
    for FILE in MISTAKES.md DEFINITION-OF-DONE.md RISKY-PATHS.md BORING.md \
                SESSION-STATE.md CLAUDE.md \
                .github/pull_request_template.md docs/adr/0000-template.md; do
        [ -f "$TEST_PROJECT/$FILE" ] || {
            echo "template not installed: $FILE" >&2
            return 1
        }
    done

    # CLAUDE.md carries the Forge addendum marker (used for idempotency).
    grep -q "Forge addendum" "$TEST_PROJECT/CLAUDE.md"

    # Test project registered for cron audits.
    [ -f "$TEST_HOME/.claude/state/audited-projects.json" ]
    jq -e --arg p "$TEST_PROJECT" 'any(.[]; .path == $p)' \
        "$TEST_HOME/.claude/state/audited-projects.json" >/dev/null

    # ── Stage 3: end-state behavior check — a hook actually fires
    # inject-mistakes-and-dod.sh reads CWD's MISTAKES.md and DOD.md and emits
    # them as injection JSON. After install-project.sh ran, both files exist;
    # the hook should produce non-empty output referencing them.
    cd "$TEST_PROJECT"
    HOOK_OUT=$(echo '{"prompt":"test"}' | bash "$REPO_ROOT/hooks/inject-mistakes-and-dod.sh" 2>/dev/null || true)
    # Output is hookSpecificOutput JSON with additionalContext containing
    # either MISTAKES or DOD content. MISTAKES.md template has "(none yet)"
    # under Entries; DOD.md has the section header "Definition of Done".
    [[ "$HOOK_OUT" == *"Definition of Done"* ]] || \
        [[ "$HOOK_OUT" == *"MISTAKES"* ]] || {
        echo "inject-mistakes-and-dod hook produced no expected content" >&2
        echo "output was: $HOOK_OUT" >&2
        return 1
    }

    # ── Stage 4: idempotency check — re-running both installers is a no-op
    run bash "$REPO_ROOT/bootstrap.sh"
    [ "$status" -eq 0 ]
    run bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT"
    [ "$status" -eq 0 ]

    # Addendum count in CLAUDE.md still 1 (not duplicated)
    count=$(grep -c "Forge addendum" "$TEST_PROJECT/CLAUDE.md")
    [ "$count" = "1" ]

    # audited-projects.json still has exactly 1 entry for this project
    pcount=$(jq --arg p "$TEST_PROJECT" '[.[] | select(.path == $p)] | length' \
        "$TEST_HOME/.claude/state/audited-projects.json")
    [ "$pcount" = "1" ]

    # Hook entries in settings.json still unique
    hcount=$(jq '[.. | objects | select(.command? != null) | select(.command | contains("must-read-before-edit.sh"))] | length' \
        "$TEST_HOME/.claude/settings.json")
    [ "$hcount" = "1" ]
}

@test "integration: bootstrap then install-project against a project with existing CLAUDE.md preserves user content" {
    # Real-world scenario: user has a CLAUDE.md before running install-project.
    # The installer must append-not-overwrite, and re-runs must not duplicate.
    cat > "$TEST_PROJECT/CLAUDE.md" <<'EOF'
# My Project's CLAUDE.md

These are the user's existing project-specific instructions.
- Always use snake_case in this repo.
- Never edit the legacy adapter without flagging.
EOF

    bash "$REPO_ROOT/bootstrap.sh" >/dev/null
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT" >/dev/null

    # User's content preserved
    grep -q "snake_case" "$TEST_PROJECT/CLAUDE.md"
    grep -q "legacy adapter" "$TEST_PROJECT/CLAUDE.md"
    # Forge addendum appended
    grep -q "Forge addendum" "$TEST_PROJECT/CLAUDE.md"

    # Re-run: still only 1 addendum block, user content still there
    bash "$REPO_ROOT/install-project.sh" "$TEST_PROJECT" >/dev/null
    count=$(grep -c "Forge addendum" "$TEST_PROJECT/CLAUDE.md")
    [ "$count" = "1" ]
    grep -q "snake_case" "$TEST_PROJECT/CLAUDE.md"
}

@test "integration: install creates the directory structure crons rely on" {
    # daily-review.sh and weekly-audit.sh both write to ~/.claude/reports/.
    # If bootstrap.sh doesn't create that dir, the first cron-fire would
    # fail. mkdir -p in the cron scripts themselves saves us, but the
    # bootstrap should land the dir up front for cleanliness.
    bash "$REPO_ROOT/bootstrap.sh" >/dev/null
    [ -d "$TEST_HOME/.claude/reports" ]
    [ -d "$TEST_HOME/.claude/state" ]
    [ -d "$TEST_HOME/.claude/forensics" ]
    [ -d "$TEST_HOME/.claude/skills" ]
    [ -d "$TEST_HOME/.claude/agents" ]
}
