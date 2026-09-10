#!/bin/zsh
set -o pipefail

# Run through macOS Terminal (for example with `open`) when an SSH session
# cannot see the Apple developer account stored in the logged-in GUI session.
# The committed Xcode project is the build input; XcodeGen is only needed after
# intentionally changing project.yml.

repo_root="${0:A:h:h}"
cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/herden-build"
derived_data="${HERDEN_DERIVED_DATA:-$cache_root/release-lane/AppDerivedData}"
source_packages="${HERDEN_SOURCE_PACKAGES:-$cache_root/source-packages}"
ios_destination="${HERDEN_IOS_BUILD_DESTINATION:-generic/platform=iOS}"
resolution_args="${HERDEN_XCODE_RESOLUTION_ARGS:-}"
build_log="${HERDEN_BUILD_LOG:-/tmp/herden-ios-device-build.log}"
build_status="${HERDEN_BUILD_STATUS:-/tmp/herden-ios-device-build.status}"
development_team="${HERDEN_DEVELOPMENT_TEAM:-}"

if [[ -z "$development_team" ]]; then
    print -u2 -- "Set HERDEN_DEVELOPMENT_TEAM to your ten-character Apple team ID."
    exit 2
fi

finish() {
    result=$?
    print -r -- "$result" > "$build_status"
    exit "$result"
}
trap finish EXIT

cd "$repo_root"
make ios-build \
    DERIVED="$derived_data" \
    SOURCE_PACKAGES="$source_packages" \
    IOS_BUILD_DESTINATION="$ios_destination" \
    DEVELOPMENT_TEAM="$development_team" \
    XCODE_RESOLUTION_ARGS="$resolution_args" \
    2>&1 | tee "$build_log"
