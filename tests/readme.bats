#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

setup() {
    REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    export REPO_ROOT
}

@test "README.md exists at repo root" {
    [ -f "$REPO_ROOT/README.md" ]
}

@test "README.md is substantive (not a stub)" {
    # Phase 0 shipped a 340-byte stub. Phase 9.1 replaces it with the real
    # docs. Assert minimum size so a future regression to a near-empty
    # README surfaces immediately.
    size=$(wc -c < "$REPO_ROOT/README.md")
    [ "$size" -gt 4000 ]
}

@test "README.md has the canonical install commands" {
    # If someone clones from a copy-paste-only mindset, the install line
    # must be present verbatim. This guards the basic onboarding flow.
    grep -qF "./bootstrap.sh" "$REPO_ROOT/README.md"
    grep -qF "./install-project.sh" "$REPO_ROOT/README.md"
}

@test "README.md documents every section required for an external reader" {
    # Reader-completeness check: install, uninstall, customize, and
    # architecture-or-how-it-works must all be present. Without these,
    # someone deciding whether to clone has incomplete information.
    grep -qiE "^## (Install|Quick start|Getting started)" "$REPO_ROOT/README.md"
    grep -qiE "^## (Uninstall|Removing)" "$REPO_ROOT/README.md"
    grep -qiE "^## (How it works|Architecture|Layers)" "$REPO_ROOT/README.md"
}

@test "README.md mentions each top-level artifact category" {
    # Sanity check that the reader learns what's inside.
    grep -qi "hooks" "$REPO_ROOT/README.md"
    grep -qi "skills" "$REPO_ROOT/README.md"
    grep -qi "subagents\|agents" "$REPO_ROOT/README.md"
    grep -qi "templates" "$REPO_ROOT/README.md"
    grep -qi "crons\|cron" "$REPO_ROOT/README.md"
}

@test "README.md does not reference user-specific or downstream-project content" {
    # The bootstrap repo is meant to be shareable. References to a
    # specific downstream project (virtual-rep / veridian / sarah / kye /
    # accrufer / a personal handle) leak private context and would
    # confuse external readers. Guard against accidental drift.
    ! grep -qiE "virtual-rep|veridian|sarah|accrufer|kye pharmaceuticals|adam blackburn|cardinalblack" "$REPO_ROOT/README.md"
}
