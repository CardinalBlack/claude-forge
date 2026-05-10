#!/usr/bin/env bats

load 'test_helper/bats-support/load'
load 'test_helper/bats-assert/load'

@test "repo skeleton exists" {
    [ -d "$HOME/.claude-bootstrap/hooks" ]
    [ -d "$HOME/.claude-bootstrap/skills" ]
    [ -d "$HOME/.claude-bootstrap/agents" ]
    [ -d "$HOME/.claude-bootstrap/templates" ]
    [ -d "$HOME/.claude-bootstrap/crons" ]
}
