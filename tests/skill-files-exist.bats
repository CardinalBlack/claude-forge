#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

@test "pre-flight-checklist skill exists with frontmatter" {
    [ -f "$REPO_ROOT/skills/pre-flight-checklist/SKILL.md" ]
    grep -q "^name: pre-flight-checklist" "$REPO_ROOT/skills/pre-flight-checklist/SKILL.md"
}

@test "definition-of-done skill exists with frontmatter" {
    [ -f "$REPO_ROOT/skills/definition-of-done/SKILL.md" ]
    grep -q "^name: definition-of-done" "$REPO_ROOT/skills/definition-of-done/SKILL.md"
}

@test "bug-postmortem skill exists with frontmatter" {
    [ -f "$REPO_ROOT/skills/bug-postmortem/SKILL.md" ]
    grep -q "^name: bug-postmortem" "$REPO_ROOT/skills/bug-postmortem/SKILL.md"
}

@test "premortem skill exists with frontmatter" {
    [ -f "$REPO_ROOT/skills/premortem/SKILL.md" ]
    grep -q "^name: premortem" "$REPO_ROOT/skills/premortem/SKILL.md"
}
