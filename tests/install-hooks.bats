#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export TEST_HOME=$(mktemp -d)
    export REAL_HOME="$HOME"
    export HOME="$TEST_HOME"
    mkdir -p "$TEST_HOME/.claude"
    SETTINGS="$TEST_HOME/.claude/settings.json"
}

teardown() {
    export HOME="$REAL_HOME"
    rm -r "$TEST_HOME" 2>/dev/null || true
}

# ---------- helpers ----------

count_command_in_settings() {
    local needle="$1"
    jq --arg n "$needle" \
       '[.. | objects | select(.command? != null) | select(.command | contains($n))] | length' \
       "$SETTINGS"
}

# ---------- tests ----------

@test "install-hooks.sh creates settings.json when missing" {
    [ ! -f "$SETTINGS" ]
    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_success
    [ -f "$SETTINGS" ]
    # All 7 manifest hook scripts are present
    for script in must-read-before-edit.sh log-read-paths.sh kill-switch.sh \
                  inject-mistakes-and-dod.sh inject-session-state.sh \
                  block-direct-main-commit.sh require-verification-before-done.sh; do
        run bash -c "jq -e --arg s \"$script\" '[.. | objects | select(.command? != null) | select(.command | contains(\$s))] | length > 0' \"$SETTINGS\""
        assert_success
    done
}

@test "install-hooks.sh merges manifest hooks without removing user hooks" {
    cat > "$SETTINGS" <<'JSON'
{
  "agentPushNotifEnabled": true,
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "USER_HOOK_MARKER" }
        ]
      }
    ]
  }
}
JSON
    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_success

    # Top-level keys preserved
    run jq -e '.agentPushNotifEnabled == true' "$SETTINGS"
    assert_success

    # User hook still present
    run jq -e '[.. | objects | select(.command? != null) | select(.command == "USER_HOOK_MARKER")] | length == 1' "$SETTINGS"
    assert_success

    # All 7 manifest hooks present
    for script in must-read-before-edit.sh log-read-paths.sh kill-switch.sh \
                  inject-mistakes-and-dod.sh inject-session-state.sh \
                  block-direct-main-commit.sh require-verification-before-done.sh; do
        run bash -c "jq -e --arg s \"$script\" '[.. | objects | select(.command? != null) | select(.command | contains(\$s))] | length == 1' \"$SETTINGS\""
        assert_success
    done
}

@test "install-hooks.sh is idempotent (no duplicates on re-run)" {
    bash "$REPO_ROOT/scripts/install-hooks.sh"
    bash "$REPO_ROOT/scripts/install-hooks.sh"
    bash "$REPO_ROOT/scripts/install-hooks.sh"

    # Each manifest hook should appear EXACTLY once
    for script in must-read-before-edit.sh log-read-paths.sh kill-switch.sh \
                  inject-mistakes-and-dod.sh inject-session-state.sh \
                  block-direct-main-commit.sh require-verification-before-done.sh; do
        count=$(jq --arg s "$script" \
            '[.. | objects | select(.command? != null) | select(.command | contains($s))] | length' \
            "$SETTINGS")
        [ "$count" = "1" ] || { echo "expected 1 of $script, got $count"; false; }
    done
}

@test "install-hooks.sh preserves top-level keys (permissions, mcpServers, enabledPlugins)" {
    cat > "$SETTINGS" <<'JSON'
{
  "permissions": {
    "allow": ["Bash(ls:*)"],
    "ask": ["Bash(rm:*)"]
  },
  "mcpServers": {
    "example": { "command": "node", "args": ["server.js"] }
  },
  "enabledPlugins": {
    "some-plugin": true
  }
}
JSON
    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_success

    run jq -e '.permissions.allow == ["Bash(ls:*)"]' "$SETTINGS"
    assert_success
    run jq -e '.permissions.ask == ["Bash(rm:*)"]' "$SETTINGS"
    assert_success
    run jq -e '.mcpServers.example.command == "node"' "$SETTINGS"
    assert_success
    run jq -e '.enabledPlugins["some-plugin"] == true' "$SETTINGS"
    assert_success
}

@test "install-hooks.sh merges into existing matcher group (no duplicate group)" {
    # Pre-create a user hook on PreToolUse with matcher "Bash" — the same
    # matcher our block-direct-main-commit hook uses.
    cat > "$SETTINGS" <<'JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "USER_BASH_HOOK" }
        ]
      }
    ]
  }
}
JSON
    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_success

    # Exactly ONE PreToolUse group with matcher "Bash"
    run jq -e '[.hooks.PreToolUse[] | select(.matcher == "Bash")] | length == 1' "$SETTINGS"
    assert_success

    # That group contains BOTH the user hook AND block-direct-main-commit
    run jq -e '
        .hooks.PreToolUse[]
        | select(.matcher == "Bash")
        | (.hooks | any(.command == "USER_BASH_HOOK"))
          and (.hooks | any(.command | contains("block-direct-main-commit.sh")))
    ' "$SETTINGS"
    assert_success
}

@test "install-hooks.sh refuses to overwrite malformed JSON settings" {
    echo 'not-json{{{' > "$SETTINGS"
    original_content=$(cat "$SETTINGS")

    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_failure
    assert_output --partial "malformed"

    # File unchanged
    [ "$(cat "$SETTINGS")" = "$original_content" ]
}

@test "install-hooks.sh renders matcher-less events without a matcher field" {
    bash "$REPO_ROOT/scripts/install-hooks.sh"

    # UserPromptSubmit groups must NOT have a matcher field
    run jq -e '[.hooks.UserPromptSubmit[] | has("matcher")] | all(. == false)' "$SETTINGS"
    assert_success

    # Stop groups must NOT have a matcher field
    run jq -e '[.hooks.Stop[] | has("matcher")] | all(. == false)' "$SETTINGS"
    assert_success

    # PreToolUse groups MUST have a matcher field
    run jq -e '[.hooks.PreToolUse[] | has("matcher")] | all(. == true)' "$SETTINGS"
    assert_success

    # PostToolUse groups MUST have a matcher field
    run jq -e '[.hooks.PostToolUse[] | has("matcher")] | all(. == true)' "$SETTINGS"
    assert_success
}

@test "install-hooks.sh renders absolute path to hook script" {
    bash "$REPO_ROOT/scripts/install-hooks.sh"
    expected="bash $REPO_ROOT/hooks/must-read-before-edit.sh"
    run jq -e --arg c "$expected" \
        '[.. | objects | select(.command? != null) | select(.command == $c)] | length == 1' \
        "$SETTINGS"
    assert_success
}

@test "install-hooks.sh prints summary line with hook count" {
    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_success
    assert_output --partial "Installed 7 hooks"
}

@test "install-hooks.sh groups UserPromptSubmit hooks together (one group, two hooks)" {
    bash "$REPO_ROOT/scripts/install-hooks.sh"

    # Both inject hooks land under the same matcher-less group
    run jq -e '
        .hooks.UserPromptSubmit
        | length == 1
        and (.[0].hooks | length == 2)
        and (.[0].hooks | any(.command | contains("inject-mistakes-and-dod.sh")))
        and (.[0].hooks | any(.command | contains("inject-session-state.sh")))
    ' "$SETTINGS"
    assert_success
}

@test "install-hooks.sh fails clearly when MANIFEST.yaml is missing" {
    # Run from a fake BOOTSTRAP_HOME with no MANIFEST.yaml
    fake_home=$(mktemp -d)
    mkdir -p "$fake_home/scripts" "$fake_home/hooks"
    cp "$REPO_ROOT/scripts/install-hooks.sh" "$fake_home/scripts/"

    run bash "$fake_home/scripts/install-hooks.sh"
    assert_failure
    assert_output --partial "MANIFEST"

    rm -r "$fake_home"
}

@test "install-hooks.sh stages temp file in settings dir (same-FS, atomic rename) and cleans up" {
    # Run install — the temp file should be staged inside ~/.claude/, not /tmp.
    # On success the trap-disarm runs and the rename consumes the temp; either
    # way no `.settings.*` leftovers should remain.
    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_success

    # No leftover staged temp files in the settings dir.
    leftovers=$(find "$TEST_HOME/.claude" -maxdepth 1 -name '.settings.*' -print)
    [ -z "$leftovers" ] || { echo "unexpected leftover staged temp files: $leftovers"; false; }
}

@test "install-hooks.sh refuses to overwrite when .hooks is not an object" {
    cat > "$SETTINGS" <<'JSON'
{"hooks": "yes"}
JSON
    original_content=$(cat "$SETTINGS")

    run bash "$REPO_ROOT/scripts/install-hooks.sh"
    assert_failure
    assert_output --partial "isn't an object"

    # File unchanged
    [ "$(cat "$SETTINGS")" = "$original_content" ]
}
