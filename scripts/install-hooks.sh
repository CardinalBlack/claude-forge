#!/usr/bin/env bash
# Idempotently merges bootstrap hooks listed in hooks/MANIFEST.yaml into the
# user's ~/.claude/settings.json.
#
# Behavior:
#   - Reads hooks/MANIFEST.yaml relative to BOOTSTRAP_HOME (the repo root).
#   - Reads or creates ~/.claude/settings.json (defaults to {} if missing).
#   - For each manifest entry:
#       * Builds a Claude Code hook entry of shape
#         {"type":"command","command":"bash <abs path to hook script>"}.
#       * Locates or creates the right matcher group under .hooks[$EVENT].
#         Matcher matching is by EXACT STRING EQUALITY.
#       * For events that take a matcher (PreToolUse, PostToolUse), the group
#         shape is {matcher, hooks}. If the YAML omits matcher, ".*" is used.
#       * For events that do NOT take a matcher (UserPromptSubmit, Stop,
#         PreCompact, SessionStart), the group shape is {hooks} only.
#       * Appends the hook to that group only if no existing hook with the
#         same `command` is present (idempotency guarantee).
#   - Atomic write: builds the new file in a temp file and `mv`s it over the
#     original. A trap cleans up the temp on early exit.
#
# IMPORTANT: The absolute path to BOOTSTRAP_HOME is baked into settings.json.
# If you move or rename the repo (e.g. ~/.claude-forge/) after install,
# the hook commands will point to dead paths. Re-run this script after any
# move to refresh the entries.

set -euo pipefail

BOOTSTRAP_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETTINGS="${HOME}/.claude/settings.json"
MANIFEST="${BOOTSTRAP_HOME}/hooks/MANIFEST.yaml"

# ---------- preflight ----------

if ! command -v yq >/dev/null 2>&1; then
    case "$(uname -s)" in
        Darwin) HINT="brew install yq" ;;
        Linux)  HINT="sudo snap install yq  # or: sudo apt-get install yq (Ubuntu 22.04+)" ;;
        *)      HINT="see https://github.com/mikefarah/yq#install" ;;
    esac
    echo "ERROR: yq is required but not installed. Install it with: ${HINT}" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required but not installed. Install it with: brew install jq (mac) or apt-get install jq (linux)" >&2
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: MANIFEST.yaml not found at ${MANIFEST}. Refusing to install." >&2
    exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"
if [ ! -f "$SETTINGS" ]; then
    echo '{}' > "$SETTINGS"
fi

# Refuse to clobber malformed settings — this is the user's hand-tuned config.
if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
    echo "ERROR: ${SETTINGS} is malformed JSON. Refusing to overwrite." >&2
    exit 1
fi

# Refuse to clobber a non-object .hooks key — gives a clear error rather than
# a cryptic jq message mid-merge. Treats absent .hooks (null) as fine.
if ! jq -e '(.hooks // {}) | type == "object"' "$SETTINGS" >/dev/null 2>&1; then
    echo "ERROR: ${SETTINGS} has a .hooks key that isn't an object. Refusing to overwrite." >&2
    echo "       Expected shape: { \"hooks\": { \"PreToolUse\": [...], \"PostToolUse\": [...], ... } }" >&2
    exit 1
fi

# ---------- atomic-merge scratch ----------

# Create the temp file in the SAME directory as the destination so the final
# `mv` is a guaranteed-atomic rename(2) instead of cross-FS copy+unlink.
# (Default mktemp uses $TMPDIR / /tmp, which on Linux is typically tmpfs while
# $HOME is on the root FS — that turns the publish into a non-atomic copy.)
TMP=$(mktemp "$(dirname "$SETTINGS")/.settings.XXXXXX")
trap 'rm -f "$TMP" "${TMP}.next"' EXIT

cp "$SETTINGS" "$TMP"

# Events that do NOT take a matcher field in Claude Code's settings.json schema.
event_takes_matcher() {
    case "$1" in
        PreToolUse|PostToolUse) return 0 ;;
        UserPromptSubmit|Stop|PreCompact|SessionStart|Notification|SubagentStop) return 1 ;;
        *) return 0 ;;  # default to "takes matcher" for forward compat
    esac
}

COUNT=$(yq '.hooks | length' "$MANIFEST")

for i in $(seq 0 $((COUNT - 1))); do
    SCRIPT=$(yq -r ".hooks[$i].script" "$MANIFEST")
    EVENT=$(yq -r ".hooks[$i].event" "$MANIFEST")
    # yq prints the literal string "null" for missing keys when -r is used.
    RAW_MATCHER=$(yq -r ".hooks[$i].matcher // \"\"" "$MANIFEST")
    [ "$RAW_MATCHER" = "null" ] && RAW_MATCHER=""

    CMD="bash ${BOOTSTRAP_HOME}/hooks/${SCRIPT}"
    HOOK_OBJ=$(jq -nc --arg c "$CMD" '{type:"command",command:$c}')

    if event_takes_matcher "$EVENT"; then
        MATCHER="$RAW_MATCHER"
        [ -z "$MATCHER" ] && MATCHER=".*"

        jq --arg event "$EVENT" \
           --arg matcher "$MATCHER" \
           --argjson hook "$HOOK_OBJ" \
           '
           .hooks //= {}
           | .hooks[$event] //= []
           | (if any(.hooks[$event][]; (.matcher // null) == $matcher) then .
              else .hooks[$event] += [{matcher:$matcher, hooks:[]}]
              end)
           | .hooks[$event] |= map(
                if (.matcher // null) == $matcher then
                    if any(.hooks[]?; .command == $hook.command) then .
                    else .hooks = ((.hooks // []) + [$hook]) end
                else . end
             )
           ' "$TMP" > "${TMP}.next"
    else
        # Matcher-less event: locate/create the single group with NO matcher key.
        jq --arg event "$EVENT" \
           --argjson hook "$HOOK_OBJ" \
           '
           .hooks //= {}
           | .hooks[$event] //= []
           | (if any(.hooks[$event][]; has("matcher") | not) then .
              else .hooks[$event] += [{hooks:[]}]
              end)
           | .hooks[$event] |= map(
                if (has("matcher") | not) then
                    if any(.hooks[]?; .command == $hook.command) then .
                    else .hooks = ((.hooks // []) + [$hook]) end
                else . end
             )
           ' "$TMP" > "${TMP}.next"
    fi

    mv "${TMP}.next" "$TMP"
done

# Final atomic publish.
mv "$TMP" "$SETTINGS"
trap - EXIT  # disarm cleanup; $TMP no longer exists

echo "Installed ${COUNT} hooks into ${SETTINGS}"
