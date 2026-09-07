#!/bin/zsh
set -o pipefail

# Run through macOS Terminal (for example with `open`) when an SSH session
# cannot see the Apple developer account stored in the logged-in GUI session.
# The committed Xcode project is the build input; XcodeGen is only needed after
# intentionally changing project.yml.

repo_root="${0:A:h:h}"
derived_data="${HERDEN_DERIVED_DATA:-/tmp/herden-ios-device-derived}"
build_log="${HERDEN_BUILD_LOG:-/tmp/herden-ios-device-build.log}"
build_status="${HERDEN_BUILD_STATUS:-/tmp/herden-ios-device-build.status}"
development_team="${HERDEN_DEVELOPMENT_TEAM:-3594Z46F6X}"

finish() {
    result=$?
    print -r -- "$result" > "$build_status"
    exit "$result"
}
trap finish EXIT

cd "$repo_root"
xcodebuild build \
    -project Heeler.xcodeproj \
    -scheme Heeler \
    -configuration Debug \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$derived_data" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$development_team" \
    CODE_SIGN_STYLE=Automatic \
    2>&1 | tee "$build_log"
