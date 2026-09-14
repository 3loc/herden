#!/bin/sh
set -eu

fail() { printf 'Herden release: %s\n' "$1" >&2; exit 1; }

[ "$#" -eq 2 ] || fail 'usage: assemble-host-release.sh <version> <release-directory>'
version=$1
release_dir=$2
repo_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)

case "$version" in
    *[!0-9.]*|.*|*.) fail 'version must be numeric X.Y.Z' ;;
esac
[ "$(printf '%s' "$version" | awk -F. '{print NF}')" -eq 3 ] \
    || fail 'version must be numeric X.Y.Z'

for asset in \
    herden-linux-x86_64 \
    herden-linux-aarch64 \
    herden-macos-x86_64 \
    herden-macos-aarch64
do
    [ -x "$release_dir/$asset" ] || fail "missing $release_dir/$asset"
    [ -s "$release_dir/$asset.sha256" ] || fail "missing checksum for $asset"
done

install -m 0644 "$repo_dir/LICENSE" "$release_dir/LICENSE"
install -m 0644 "$repo_dir/NOTICE" "$release_dir/NOTICE"
install -m 0755 "$repo_dir/install.sh" "$release_dir/install.sh"

linux_x86_64=$(awk '{print $1; exit}' "$release_dir/herden-linux-x86_64.sha256")
linux_aarch64=$(awk '{print $1; exit}' "$release_dir/herden-linux-aarch64.sha256")
macos_x86_64=$(awk '{print $1; exit}' "$release_dir/herden-macos-x86_64.sha256")
macos_aarch64=$(awk '{print $1; exit}' "$release_dir/herden-macos-aarch64.sha256")

sed \
    -e "s/@VERSION@/$version/g" \
    -e "s/@LINUX_X86_64@/$linux_x86_64/g" \
    -e "s/@LINUX_AARCH64@/$linux_aarch64/g" \
    -e "s/@MACOS_X86_64@/$macos_x86_64/g" \
    -e "s/@MACOS_AARCH64@/$macos_aarch64/g" \
    "$repo_dir/scripts/latest-host-release.json.in" > "$release_dir/latest.json"

printf 'Assembled Herden Host %s in %s\n' "$version" "$release_dir"
