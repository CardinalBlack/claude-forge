#!/usr/bin/env bash
# PreToolUse hook: scans the staged diff before `git commit` runs and
# refuses the commit if known-malicious patterns appear in the additions.
# Layer 1 of the prompt-injection defense suite.
#
# Patterns detected (any one triggers a block):
#   1. curl/wget piped to a shell  (curl ... | sh / bash / zsh)
#   2. New `eval(` or `new Function(` in JS/TS additions
#   3. New install hooks in package.json (postinstall/preinstall/prepare/
#      prepublish/prepack)
#   4. Newly added *.sh / *.bash files outside allow-listed dirs
#      (scripts/, bin/, hooks/, crons/, .husky/)
#   5. Modified .github/workflows/*.yml
#   6. Hidden Unicode in additions (zero-width, RTL/LTR override, BOM)
#   7. Long base64-looking blobs (80+ consecutive [A-Za-z0-9+/=])
#   8. Paths outside the project root (+++ b/../, absolute paths)
#
# Override: include the literal string `INJECTION-SCAN-OVERRIDE:` anywhere in
# the `git commit -m "..."` message.
#
# Fail-open: missing jq, malformed JSON, git not in a repo, no staged diff,
# or any unexpected hook error → exit 0 (we'd rather miss than brick).
set -euo pipefail

PAYLOAD=$(cat -)

TOOL=$(jq -r '.tool_name // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ "$TOOL" = "Bash" ] || exit 0

CMD=$(jq -r '.tool_input.command // empty' <<< "$PAYLOAD" 2>/dev/null) || exit 0
[ -n "$CMD" ] || exit 0

# Match any commit invocation (avoid commit-tree / commit-graph), including the
# quiet-git.sh wrapper and `git -c <cfg> commit` — these used to bypass the scan.
echo "$CMD" | grep -qE 'git([[:space:]]+-c[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)|quiet-git\.sh[[:space:]]+commit([[:space:]]|$)' || exit 0

# Override tag in the commit command (typically in -m "..." text).
echo "$CMD" | grep -q 'INJECTION-SCAN-OVERRIDE:' && exit 0

# Past this point: nothing should ever take us down. Soft-fail any leftover
# errors so the hook can't brick `git commit` on a corner case.
set +e

DIFF=$(git diff --cached 2>/dev/null)
DIFF_RC=$?
[ $DIFF_RC -ne 0 ] && exit 0
[ -z "$DIFF" ] && exit 0

# Findings buffer: each line is "Pattern name|first matching line".
FINDINGS=""

add_finding() {
    # $1 = pattern name, $2 = sample line (trim to ~200 chars to keep stderr sane)
    local name="$1"
    local sample="$2"
    sample=$(printf '%s' "$sample" | tr -d '\r' | cut -c1-200)
    # Only record the first hit per pattern.
    if ! printf '%s' "$FINDINGS" | grep -qF "$name|"; then
        FINDINGS="${FINDINGS}${name}|${sample}
"
    fi
}

# ----- Walk the diff once, tracking current file -----
# We need per-file context for patterns 2 (JS/TS only), 4 (sh/bash only), 5
# (workflows), 8 (path sanity). Patterns 1, 6, 7 are content-only — but it's
# cheaper to walk once.

CUR_FILE=""
CUR_EXT=""

# Use process substitution + while-read to keep variables in this shell.
while IFS= read -r line; do
    # Track current file from `+++ b/path` headers.
    case "$line" in
        '+++ '*)
            # Strip leading "+++ b/" if present; tolerate "+++ /dev/null".
            path="${line#+++ }"
            path="${path#b/}"
            CUR_FILE="$path"
            # Extract lowercase extension.
            case "$CUR_FILE" in
                *.*) CUR_EXT="${CUR_FILE##*.}" ;;
                *)   CUR_EXT="" ;;
            esac

            # Pattern 5: modified workflows.
            if printf '%s' "$CUR_FILE" | grep -qE '^\.github/workflows/.+\.ya?ml$'; then
                add_finding "Modified .github/workflows" "$line"
            fi

            # Pattern 8: paths outside repo root. Allow `+++ /dev/null`
            # (deletion marker) but flag anything else starting with `/` or
            # containing `../` traversal.
            if [ "$line" != "+++ /dev/null" ]; then
                if printf '%s' "$line" | grep -qE '^\+\+\+ b/\.\./|^\+\+\+ /'; then
                    add_finding "Path outside project root" "$line"
                fi
            fi
            continue
            ;;
        '--- '*)
            continue
            ;;
        '+++'*|'---'*)
            # `+++` or `---` without the space — not a header; fall through.
            ;;
    esac

    # Only inspect addition lines (start with `+` but not `+++`).
    case "$line" in
        '+++'*) continue ;;
        '+'*)   : ;;  # addition — process below
        *)      continue ;;
    esac

    # ----- Pattern 1: curl/wget piped to shell -----
    if printf '%s' "$line" | grep -qE '(curl|wget)[^|]*\|[[:space:]]*(sh|bash|zsh)([[:space:]]|$)'; then
        add_finding "curl/wget piped to shell" "$line"
    fi

    # ----- Pattern 2: eval( / new Function( in JS/TS additions -----
    case "$CUR_EXT" in
        js|jsx|ts|tsx|mjs|cjs)
            # Require non-identifier char before `eval` / `new` to avoid
            # `someeval(` or `renew Function(` false positives.
            if printf '%s' "$line" | grep -qE '(^\+|[^A-Za-z0-9_])(eval\(|new[[:space:]]+Function\()'; then
                add_finding "eval/new Function in JS/TS" "$line"
            fi
            ;;
    esac

    # ----- Pattern 3: install hooks in package.json -----
    case "$CUR_FILE" in
        *package.json|*/package.json|package.json)
            if printf '%s' "$line" | grep -qE '"(postinstall|preinstall|prepare|prepublish|prepack)":[[:space:]]*"'; then
                add_finding "package.json install hook" "$line"
            fi
            ;;
    esac

    # ----- Pattern 6: hidden Unicode -----
    # Zero-width space (U+200B, e2 80 8b), ZWNJ (e2 80 8c), ZWJ (e2 80 8d),
    # LTR override (e2 80 ad), RTL override (e2 80 ae), BOM (ef bb bf).
    if printf '%s' "$line" | LC_ALL=C grep -qE $'\xe2\x80[\x8b-\x8d]|\xe2\x80[\xad\xae]|\xef\xbb\xbf'; then
        add_finding "Hidden Unicode (zero-width/RTL/BOM)" "$line"
    fi

    # ----- Pattern 7: long base64 blob -----
    if printf '%s' "$line" | grep -qE '[A-Za-z0-9+/=]{80,}'; then
        add_finding "Long base64-like blob (80+ chars)" "$line"
    fi
done <<< "$DIFF"

# ----- Pattern 4: newly-added shell scripts outside allow-list -----
# A "newly added" file in `git diff --cached` shows `new file mode` followed by
# a `+++ b/path` line. Walk the diff headers to detect new shell scripts.
NEW_FILES=$(printf '%s\n' "$DIFF" | awk '
    /^diff --git / { file=""; isnew=0; next }
    /^new file mode/ { isnew=1; next }
    /^\+\+\+ b\// {
        if (isnew) {
            path = substr($0, 7)
            print path
        }
        isnew=0
    }
')

while IFS= read -r path; do
    [ -z "$path" ] && continue
    case "$path" in
        *.sh|*.bash) : ;;
        *) continue ;;
    esac
    # Allow-list dirs.
    case "$path" in
        scripts/*|*/scripts/*) continue ;;
        bin/*|*/bin/*)         continue ;;
        hooks/*|*/hooks/*)     continue ;;
        crons/*|*/crons/*)     continue ;;
        .husky/*|*/.husky/*)   continue ;;
    esac
    add_finding "New shell script outside allow-list" "+++ b/$path"
done <<< "$NEW_FILES"

# ----- Verdict -----
if [ -z "$FINDINGS" ]; then
    exit 0
fi

{
    echo "BLOCKED: pre-commit injection scan flagged the staged diff:"
    echo
    # Print one bullet per finding.
    printf '%s' "$FINDINGS" | while IFS='|' read -r name sample; do
        [ -z "$name" ] && continue
        echo "  - ${name}: ${sample}"
    done
    echo
    echo "If these are intentional, append to the commit message:"
    echo "    INJECTION-SCAN-OVERRIDE: <one-sentence reason>"
} >&2
exit 2
