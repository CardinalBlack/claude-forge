#!/usr/bin/env bash
# PreToolUse hook: scans the staged diff before a commit and REFUSES the commit
# if it adds anything that looks like a live credential/key. This is the
# CONTENT scanner the suite was missing — the filename block (*.env*/*secret*)
# and the injection scanner (scan-commit-diff.sh) do NOT detect keys pasted
# inline into .md/.ts/.json files.
#
# (Named scan-keys.sh, not scan-secrets.sh, because the global Write-block hook
# refuses any path containing "secret".)
#
# Why this exists: a session committed live Langfuse keys (pk-lf-/sk-lf-)
# verbatim into a handoff .md; nothing caught it. They're in git history now.
#
# Triggers on ANY commit invocation, including the quiet-git.sh wrapper that the
# injection scanner's `git commit` literal-match used to miss:
#   - `git commit ...`
#   - `git -c core.hooksPath=/dev/null commit ...`
#   - `bash scripts/quiet-git.sh commit ...`  (and any *quiet-git.sh commit)
#
# Override: include `KEY-SCAN-OVERRIDE: <reason>` in the commit message
# (use ONLY for verified false positives / intentionally-public test fixtures).
#
# Fail-open on every error path (no jq, bad JSON, not a repo, no diff) → exit 0.
# We refuse (exit 2) ONLY on a positive match.
set -euo pipefail

PAYLOAD=$(cat -)

TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(jq -r '.tool_input.command // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Trigger on any commit invocation: real git commit OR the quiet-git wrapper.
if ! echo "$CMD" | grep -qE 'git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)|quiet-git\.sh[[:space:]]+commit([[:space:]]|$)'; then
    exit 0
fi

# Verified-false-positive override.
echo "$CMD" | grep -q 'KEY-SCAN-OVERRIDE:' && exit 0

# Past here, soft-fail everything so we can never brick a commit on a corner case.
set +e

DIFF=$(git diff --cached 2>/dev/null)
[ $? -ne 0 ] && exit 0
[ -z "$DIFF" ] && exit 0

# Only inspect ADDED lines (start with '+' but not the '+++' file header).
ADDED=$(printf '%s\n' "$DIFF" | grep -E '^\+' | grep -vE '^\+\+\+')
[ -z "$ADDED" ] && exit 0

FINDINGS=""
flag() {
    # $1 = label, $2 = ERE pattern
    local hit
    hit=$(printf '%s\n' "$ADDED" | grep -aoE "$2" | head -n1)
    if [ -n "$hit" ]; then
        # Mask the middle so we never echo the full key into logs/stderr.
        local masked="${hit:0:10}…${hit: -4}"
        FINDINGS="${FINDINGS}  - ${1}: ${masked}
"
    fi
}

flag "Anthropic key"        'sk-ant-[A-Za-z0-9_-]{20,}'
flag "Langfuse public key"  'pk-lf-[0-9a-fA-F-]{20,}'
flag "Langfuse secret key"  'sk-lf-[0-9a-fA-F-]{20,}'
flag "Stripe live secret"   'sk_live_[A-Za-z0-9]{16,}'
flag "Stripe live key"      '[pr]k_live_[A-Za-z0-9]{16,}'
flag "OpenAI-style key"     'sk-[A-Za-z0-9]{20,}'
flag "AWS access key id"    'AKIA[0-9A-Z]{16}'
flag "Google API key"       'AIza[0-9A-Za-z_-]{35}'
flag "GitHub token"         'gh[poursu]_[A-Za-z0-9]{36}'
flag "GitLab PAT"           'glpat-[A-Za-z0-9_-]{20}'
flag "Slack token"          'xox[baprs]-[A-Za-z0-9-]{10,}'
flag "age secret key"       'AGE-SECRET-KEY-1[0-9A-Z]{20,}'
flag "PEM private key"      '-----BEGIN [A-Z ]*PRIVATE KEY-----'
flag "JWT"                  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
flag "Bearer token"         'Bearer [A-Za-z0-9._-]{20,}'

[ -z "$FINDINGS" ] && exit 0

{
    echo "BLOCKED: credential-content scan found likely live keys in the staged diff:"
    echo
    printf '%s' "$FINDINGS"
    echo
    echo "Keys must NEVER be committed (handoffs/.md included — git history is forever)."
    echo "Redact when preserving a trace (e.g. pk-lf-…REDACTED). Real keys: 1Password / .env only."
    echo "If this is a verified false positive, append to the commit message:"
    echo "    KEY-SCAN-OVERRIDE: <one-sentence reason>"
} >&2
exit 2
