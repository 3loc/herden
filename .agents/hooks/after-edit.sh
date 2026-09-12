#!/bin/sh
# Advisory only — PostToolUse cannot block, and a hook that cries wolf gets
# switched off. Each notice fires at most once per session, keyed by a marker
# in the session scratchpad.
set -eu

input=$(cat)
path=$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')
scratch=$(printf '%s' "$input" | jq -r '.scratchpad_dir // ""')
[ -n "$path" ] || exit 0

say() {
    marker="${scratch:-/tmp}/.herden-hook-$1"
    [ -e "$marker" ] && exit 0
    : > "$marker" 2>/dev/null || true
    jq -n --arg m "$2" '{hookSpecificOutput:{hookEventName:"PostToolUse",systemMessage:$m}}'
    exit 0
}

case "$path" in
    */project.yml|project.yml)
        say project-yml "project.yml changed. The committed Herden.xcodeproj must stay in sync: run 'make generate' on macOS and commit the regenerated project alongside this change (CLAUDE.md > Conventions). Do not hand-edit MARKETING_VERSION."
        ;;
esac

case "$path" in
    */Sources/Herden/*|Sources/Herden/*)
        git diff --quiet -- CHANGELOG.md 2>/dev/null || exit 0
        say changelog "App source changed with no CHANGELOG.md edit in the working tree. User-visible changes get an entry under [Unreleased]; internal refactors and test work stay out of it (CLAUDE.md > Conventions). Ignore this if the change is internal."
        ;;
esac

exit 0
