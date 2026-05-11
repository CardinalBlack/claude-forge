#!/usr/bin/env bash
# PreToolUse hook: before `git commit` runs, check whether any staged file
# matches a glob pattern from the project's RISKY-PATHS.md. If so, shell out
# to the Claude CLI for a security/correctness review of the diff and block
# the commit unless the review returns "No risks detected" (or the user
# included a SKIP-RISKY-REVIEW: override tag in the commit message).
#
# Layer 5 of the prompt-injection defense suite. Designed to be advisory:
# every failure mode (no claude CLI, no jq, glob parser error, claude
# timeout, claude non-zero exit) is fail-open. The ONLY case where this
# hook blocks is:
#   (a) RISKY-PATHS.md exists and matched at least one staged file,
#   (b) the review produced a verdict,
#   (c) that verdict did NOT contain "No risks detected" (case-insensitive),
#   (d) the commit command did NOT contain SKIP-RISKY-REVIEW:.
#
# Override: include the literal string `SKIP-RISKY-REVIEW: <reason>` in the
# commit command (typically inside the -m "..." text). The hook short-circuits
# BEFORE invoking claude so override commits don't burn tokens.
set -euo pipefail

PAYLOAD=$(cat -)

# Fail-open on malformed JSON / missing jq.
TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(jq -r '.tool_input.command // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Tightened: require whitespace-or-EOL after "commit" so we don't match
# `git commit-tree` or `git commit-graph`.
echo "$CMD" | grep -qE 'git[[:space:]]+commit([[:space:]]|$)' || exit 0

# Override short-circuit: skip BEFORE invoking claude (don't burn tokens).
echo "$CMD" | grep -q 'SKIP-RISKY-REVIEW:' && exit 0

# No RISKY-PATHS.md in CWD → no-op.
[ -f RISKY-PATHS.md ] || exit 0

# claude CLI required for the review pass. If absent, fail-open: we can't
# review, but we also shouldn't block on tooling gaps.
command -v claude >/dev/null 2>&1 || exit 0

# From here on: soft-fail. An unexpected error during pattern parsing or
# diff inspection should never brick `git commit`.
set +e

STAGED_FILES=$(git diff --cached --name-only 2>/dev/null)
[ -z "$STAGED_FILES" ] && exit 0

# Extract glob patterns from backticked items in bullet points.
# Pattern: lines starting with optional whitespace, then "- ", then content
# with at least one backtick pair. Pull every backticked segment from each
# such line (allows multiple patterns per bullet, though uncommon).
PATTERNS=$(awk -F'`' '
    /^[[:space:]]*- `/ {
        for (i = 2; i <= NF; i += 2) {
            if ($i != "") print $i
        }
    }
' RISKY-PATHS.md 2>/dev/null)

[ -z "$PATTERNS" ] && exit 0

# Glob matching via Python. Handles `**` recursive globs and `{a,b}` brace
# expansion by manual regex conversion. fnmatch alone treats `*` as
# non-slash-crossing only partially; the conversion below is explicit so we
# match what shell globstar would match against a flat path string.
MATCHED=$(python3 - "$STAGED_FILES" "$PATTERNS" <<'PY' 2>/dev/null
import sys, re

files = [f for f in sys.argv[1].split("\n") if f]
patterns = [p for p in sys.argv[2].split("\n") if p]

def expand_braces(pat):
    # Minimal {a,b,c} expansion. Returns a list of patterns.
    m = re.search(r'\{([^{}]*)\}', pat)
    if not m:
        return [pat]
    pre, post = pat[:m.start()], pat[m.end():]
    out = []
    for alt in m.group(1).split(","):
        out.extend(expand_braces(pre + alt + post))
    return out

def glob_to_regex(pat):
    # Convert a shell-style glob with `**` to a regex matching the full path.
    # Strategy: walk the pattern char-by-char; `**` matches any chars
    # (including `/`); `*` matches non-slash; `?` matches a single non-slash;
    # `[...]` passes through as a char class; everything else escaped.
    i, n = 0, len(pat)
    out = ["^"]
    while i < n:
        c = pat[i]
        if c == "*":
            if i + 1 < n and pat[i + 1] == "*":
                # `**` — match anything including slashes.
                out.append(".*")
                i += 2
                # Eat a trailing slash so `**/foo` matches `foo` at root too.
                if i < n and pat[i] == "/":
                    # Allow `**/x` to match `x` (zero dirs) as well as `a/b/x`.
                    out[-1] = "(?:.*/)?"
                    i += 1
            else:
                out.append("[^/]*")
                i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c == "[":
            # Pass through char class verbatim until closing ].
            j = i + 1
            if j < n and pat[j] == "!":
                pat = pat[:j] + "^" + pat[j+1:]
            while j < n and pat[j] != "]":
                j += 1
            out.append(pat[i:j+1] if j < n else re.escape(pat[i:]))
            i = j + 1
        else:
            out.append(re.escape(c))
            i += 1
    out.append("$")
    return "".join(out)

compiled = []
for raw in patterns:
    for expanded in expand_braces(raw):
        try:
            compiled.append(re.compile(glob_to_regex(expanded)))
        except re.error:
            continue

matched = []
for f in files:
    for rx in compiled:
        if rx.match(f):
            matched.append(f)
            break

print("\n".join(matched))
PY
)
PY_RC=$?

# If python crashed or produced nothing useful, fail-open.
[ $PY_RC -ne 0 ] && exit 0
[ -z "$MATCHED" ] && exit 0

# Build a truncated diff snippet (max ~4KB) for the matched files only.
# Per-file `git diff --cached -- <path>`, concatenated, head-truncated.
DIFF_SNIPPET=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    chunk=$(git diff --cached -- "$f" 2>/dev/null)
    DIFF_SNIPPET="${DIFF_SNIPPET}
=== ${f} ===
${chunk}
"
done <<< "$MATCHED"

# Truncate to ~4KB (4096 bytes) to keep token cost predictable.
DIFF_SNIPPET=$(printf '%s' "$DIFF_SNIPPET" | head -c 4096)

# Files list (newline-separated) for the prompt.
FILE_LIST=""
while IFS= read -r f; do
    [ -z "$f" ] && continue
    FILE_LIST="${FILE_LIST}  - ${f}
"
done <<< "$MATCHED"

PROMPT="You are reviewing a git diff for security and correctness risk. The following files are in the project's RISKY-PATHS.md (paths that require extra scrutiny). Report any concerns in 3-5 bullet points. If you see nothing concerning, say 'No risks detected' explicitly. Be terse.

Files:
${FILE_LIST}
Diff (truncated):
${DIFF_SNIPPET}"

# Choose a timeout wrapper that's actually on PATH. macOS doesn't ship
# `timeout`; coreutils provides `gtimeout` via Homebrew. If neither is
# available, run claude directly — fail-open handles a hung process less
# gracefully but advisory hooks shouldn't hard-depend on coreutils.
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout 60"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout 60"
fi

if [ -n "$TIMEOUT_CMD" ]; then
    REVIEW=$($TIMEOUT_CMD claude --print --model sonnet-4-6 "$PROMPT" 2>&1)
else
    REVIEW=$(claude --print --model sonnet-4-6 "$PROMPT" 2>&1)
fi
CLAUDE_RC=$?

# Fail-open on claude error/timeout.
[ $CLAUDE_RC -ne 0 ] && exit 0
[ -z "$REVIEW" ] && exit 0

# Print the review with a banner regardless of verdict (transparency).
{
    echo "───── Risky-path review (Sonnet) ─────"
    echo "Matched files:"
    printf '%s' "$FILE_LIST"
    echo
    echo "Review:"
    echo "$REVIEW"
    echo "──────────────────────────────────────"
} >&2

# Verdict: "No risks detected" (case-insensitive) → allow.
if printf '%s' "$REVIEW" | grep -qi 'No risks detected'; then
    exit 0
fi

# Otherwise block, with override instructions.
cat >&2 <<MSG

BLOCKED: risky-path review flagged concerns. Either:
  (a) address the concerns above, re-stage, and retry; or
  (b) override by including in the commit message:
        SKIP-RISKY-REVIEW: <one-sentence reason>
MSG
exit 2
