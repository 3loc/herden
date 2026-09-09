#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
destination=${1:-platform=iOS Simulator,name=iPhone 17}
derived_data=${HERDEN_SSH_DERIVED_DATA:-$repo_root/build/HerdenSSHDerivedData}
test_log=$(mktemp -t herden-ssh-tests.XXXXXX)

cleanup() {
    rm -f "$test_log"
}
trap cleanup EXIT

(
    cd "$repo_root/Packages/HerdenSSH"
    xcodebuild test \
        -scheme HerdenSSH \
        -destination "$destination" \
        -derivedDataPath "$derived_data" \
        -collect-test-diagnostics never
) 2>&1 | tee "$test_log"

total=$(sed -n \
    's/^.*Test run with \([0-9][0-9]*\) tests in .* passed after .*$/\1/p' \
    "$test_log" | tail -n 1)
if [[ -z "$total" ]]; then
    echo "The HerdenSSH package suite printed no passing run summary" >&2
    exit 1
fi

skips=$(grep -c 'Test .* skipped:' "$test_log" || true)
executed=$((total - skips))
if ((executed <= 0)); then
    echo "The HerdenSSH package suite executed no tests ($total registered, $skips skipped)" >&2
    exit 1
fi

echo "HerdenSSH package suite executed $executed of $total tests ($skips skipped)."
